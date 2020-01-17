package main

import (
	"bufio"
	"crypto/tls"
	"io/ioutil"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

type proxy struct {
	target      *url.URL
	impersonate bool
	insecure    bool
}

var proxies = make(map[string]map[string]*proxy)
var host = os.Getenv("PROXY_HOST")
var user = os.Getenv("DOCKER_USER")
var homedest = os.Getenv("HOMEDEST")
var secret = os.Getenv("SECRET")
var passThroughProxy *httputil.ReverseProxy
var reverseProxy *httputil.ReverseProxy
var reverseProxyInsecure *httputil.ReverseProxy

func init() {
	passThroughProxy = &httputil.ReverseProxy{
		Director:       passThroughDirector,
		ModifyResponse: modifyResponse,
	}
	transportInsecure := http.DefaultTransport.(*http.Transport)
	configInsecure := &tls.Config{InsecureSkipVerify: true}
	transportInsecure.TLSClientConfig = configInsecure
	reverseProxyInsecure = &httputil.ReverseProxy{
		Director:       reverseDirector,
		ModifyResponse: modifyResponse,
		Transport:      transportInsecure,
	}
	reverseProxy = &httputil.ReverseProxy{
		Director:       reverseDirector,
		ModifyResponse: modifyResponse,
	}

	log.Printf("homedest: %s", homedest)
}

func main() {
	fileInfos, err := ioutil.ReadDir("/config")
	if err != nil {
		log.Fatal(err)
	}

	for _, fileInfo := range fileInfos {
		app := fileInfo.Name()
		file, err := os.Open("/config/" + app)
		if err != nil {
			log.Fatal(err)
		}
		defer file.Close()

		proxies[app] = make(map[string]*proxy)
		scanner := bufio.NewScanner(file)
		for scanner.Scan() {
			split := strings.Split(scanner.Text(), "=")
			if len(split) == 2 {
				defineProxy(app, split[0], split[1])
			}
		}

		if err := scanner.Err(); err != nil {
			log.Fatal(err)
		}
	}

	// Redirect http to https
	go http.ListenAndServe(":80", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		url := r.URL
		url.Host = r.Host
		url.Scheme = "https"
		http.Redirect(w, r, url.String(), http.StatusMovedPermanently)
	}))

	crt := "/certificates/" + host + ".crt"
	key := "/certificates/" + host + ".key"
	log.Fatal(http.ListenAndServeTLS(":443", crt, key, http.HandlerFunc(handler)))
}

func handler(w http.ResponseWriter, r *http.Request) {
	log.Printf("%s %s %s", r.RemoteAddr, r.Method, r.RequestURI)
	if r.Method == "OPTIONS" {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, PUT, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "SOAPAction, X-Requested-With, Origin, Content-Type, Authorization, Accept")
	} else if r.URL.Path == "/" {
		if r.URL.Query().Get("url") == "" && homedest != "" {
			http.Redirect(w, r, homedest, http.StatusFound)
		} else {
			passThroughProxy.ServeHTTP(w, r)
		}
	} else {
		reverse(w, r)
	}
}

func defineProxy(app, key, value string) {
	impersonate, insecure := false, false
	if strings.HasPrefix(value, "impersonate,") || strings.HasPrefix(value, "insecure,") {
		split := strings.SplitN(value, ",", 2)
		impersonate = (split[0] == "impersonate")
		insecure = (split[0] == "insecure")
		value = split[1]
	}
	if strings.HasPrefix(value, "impersonate,") || strings.HasPrefix(value, "insecure,") {
		split := strings.SplitN(value, ",", 2)
		impersonate = (split[0] == "impersonate")
		insecure = (split[0] == "insecure")
		value = split[1]
	}
	target, _ := url.Parse(value)
	if target.Path == "" {
		target.Path = "/"
	}
	key = "/" + key + "/"
	proxies[app][key] = &proxy{
		target:      target,
		impersonate: impersonate,
		insecure:    insecure,
	}
	log.Printf("reversing: %s%s -> %v impersonate=%t insecure=%t", app, key, target, impersonate, insecure)
}

func reverse(w http.ResponseWriter, r *http.Request) {
	path := "/"
	requestParts := strings.Split(r.URL.Path, "/")
	app := requestParts[1]
	if _, ok := proxies[app]; ok {
		// Normal case: path starts with app directory
		if len(requestParts) > 2 {
			path += strings.SplitN(r.URL.Path, "/", 3)[2] // alles na de tweede slash
		}
		// log.Printf("app=%s path=%s", app, path)
	} else {
		// Naughty components case: missing app directory; try referer
		referer, _ := url.Parse(r.Referer() + "/") //  + "/" to cater for empty Referer
		app = strings.Split(referer.Path, "/")[1]
		path = r.URL.Path
		log.Printf("Trying referer: app=%s path=%s", app, path)
	}
	if _, ok := proxies[app]; !ok {
		// Last resort (also helping old single-proxy clients): try DOCKER_USER
		app = user
		log.Printf("Trying DOCKER_USER: app=%s path=%s", app, path)
	}
	for key, proxy := range proxies[app] {
		if path+"/" == key {
			path = path + "/"
		}
		if strings.HasPrefix(path, key) {
			target := proxy.target
			r.URL.Scheme = target.Scheme
			r.URL.Host = target.Host
			r.URL.Path = target.Path + strings.SplitN(path, "/", 3)[2] // alles na de tweede slash
			if proxy.impersonate {
				r.Host = host
				if target.Port() != "" {
					r.Host += ":" + target.Port()
				}
			} else {
				r.Host = target.Host
			}
			if proxy.insecure {
				reverseProxyInsecure.ServeHTTP(w, r)
			} else {
				reverseProxy.ServeHTTP(w, r)
			}
			return
		}
		// if strings.HasPrefix(r.URL.Path, key) {
		// 	r.URL.Scheme = target.Scheme
		// 	r.URL.Host = target.Host
		// 	r.URL.Path = target.Path + strings.SplitN(r.URL.Path, "/", 3)[2] // alles na de tweede slash
		// 	referer, _ := url.Parse(r.Referer())
		// 	if key == "/api/" {
		// 		r.Host = host
		// 		if target.Port() != "" {
		// 			r.Host += ":" + target.Port()
		// 		}
		// 		reverseProxyInsecure.ServeHTTP(w, r)
		// 	} else if (r.FormValue("secret") != secret) && (key == "/print/" ||
		// 		key == "/mapfish/" ||
		// 		(key == "/geoserver/" && r.FormValue("service") != "" && !strings.HasPrefix(referer.Path, key))) {
		// 		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		// 	} else {
		// 		r.Host = target.Host
		// 		if strings.Contains(target.Hostname(), ".") {
		// 			reverseProxy.ServeHTTP(w, r)
		// 		} else {
		// 			reverseProxyInsecure.ServeHTTP(w, r)
		// 		}
		// 	}
		// 	return
		// }
	}
	http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
}

func reverseDirector(r *http.Request) {
	log.Printf("%s %s reverse %v %v", r.RemoteAddr, r.Method, r.Host, r.URL)
	if _, ok := r.Header["User-Agent"]; !ok {
		// explicitly disable User-Agent so it's not set to default value
		r.Header.Set("User-Agent", "")
	}
}

func passThroughDirector(r *http.Request) {
	if target, err := url.Parse(r.FormValue("url")); err != nil {
		log.Printf("%+v", err)
	} else {
		query := r.URL.Query()
		query.Del("url")
		target.RawQuery = query.Encode()
		r.URL = target
		r.Host = target.Host
		log.Printf("%s %s passthrough %v", r.RemoteAddr, r.Method, r.URL)
	}
}

func modifyResponse(r *http.Response) error {
	r.Header.Set("Access-Control-Allow-Origin", "*")
	// Deze twee hieronder zouden eigenlijk niet nodig moeten zijn, maar het blijkt er wel beter van te worden..
	r.Header.Set("Access-Control-Allow-Methods", "GET, PUT, POST, DELETE, OPTIONS")
	r.Header.Set("Access-Control-Allow-Headers", "SOAPAction, X-Requested-With, Origin, Content-Type, Authorization, Accept")
	return nil
}
