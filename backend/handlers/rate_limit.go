package handlers

import (
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

type ipLimiter struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

var (
	ipLimiters = make(map[string]*ipLimiter)
	ipMu       sync.Mutex
)

// DEMO ONLY: daca TRUST_XFF=true, atunci folosim X-Forwarded-For ca IP client.
// In productie: TRUST_XFF trebuie false (sau validat strict pe proxy de incredere).
var trustXFF = strings.ToLower(os.Getenv("TRUST_XFF")) == "true"

func clientIP(r *http.Request) string {
	if trustXFF {
		xff := r.Header.Get("X-Forwarded-For")
		if xff != "" {
			// primul IP din lista
			parts := strings.Split(xff, ",")
			ip := strings.TrimSpace(parts[0])
			if ip != "" {
				return ip
			}
		}
	}

	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func RateLimitLogin(next http.HandlerFunc) http.HandlerFunc {
	// Ajusteaza pentru demo:
	// ~10 requesturi/minut/IP, burst 10
	limit := rate.Every(6 * time.Second)
	burst := 10

	// cleanup ca sa nu creasca map-ul
	go func() {
		t := time.NewTicker(5 * time.Minute)
		defer t.Stop()
		for range t.C {
			ipMu.Lock()
			for ip, v := range ipLimiters {
				if time.Since(v.lastSeen) > 15*time.Minute {
					delete(ipLimiters, ip)
				}
			}
			ipMu.Unlock()
		}
	}()

	return func(w http.ResponseWriter, r *http.Request) {
		ip := clientIP(r)

		ipMu.Lock()
		lim, ok := ipLimiters[ip]
		if !ok {
			lim = &ipLimiter{
				limiter:  rate.NewLimiter(limit, burst),
				lastSeen: time.Now(),
			}
			ipLimiters[ip] = lim
		}
		lim.lastSeen = time.Now()
		allowed := lim.limiter.Allow()
		ipMu.Unlock()

		if !allowed {
			http.Error(w, `{"error":"Too many attempts"}`, http.StatusTooManyRequests)
			return
		}
		next(w, r)
	}
}
