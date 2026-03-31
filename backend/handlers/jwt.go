package handlers

import (
	"errors"
	"net/http"

	"github.com/golang-jwt/jwt/v5"
)

// getTokenFromRequest: ia token din cookie auth_token sau din Authorization: Bearer <token>
func getTokenFromRequest(r *http.Request) string {
	// Din cookie
	if cookie, err := r.Cookie("auth_token"); err == nil {
		return cookie.Value
	}
	// Din header
	auth := r.Header.Get("Authorization")
	if auth != "" && len(auth) > 7 && auth[:7] == "Bearer " {
		return auth[7:]
	}
	return ""
}

func getUserIDFromRequest(r *http.Request) (int, error) {
	tokenStr := getTokenFromRequest(r)
	if tokenStr == "" {
		return 0, errors.New("Neautentificat")
	}
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})
	if err != nil || !token.Valid {
		return 0, errors.New("invalid token")
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return 0, errors.New("invalid claims")
	}

	// jwt.MapClaims ajunge deseori float64 la decode.
	raw := claims["user_id"]
	switch v := raw.(type) {
	case float64:
		return int(v), nil
	case int:
		return v, nil
	default:
		return 0, errors.New("user_id lipseste sau are tip invalid")
	}
}
