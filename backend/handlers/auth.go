package handlers

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"Break-the-Login/backend/db"

	"golang.org/x/crypto/bcrypt"
)

// Cheie JWT - vulnerabila: hardcodata in cod
var jwtSecret = []byte("secretdiscret456")

type RegisterRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

const (
	maxFailedLogins = 5
	lockoutFor      = 10 * time.Minute
)

// Register vulnerabil: accepta parole slabe, fara validare
func Register(w http.ResponseWriter, r *http.Request) {
	var req RegisterRequest
	json.NewDecoder(r.Body).Decode(&req)

	//fara validare - lungime si complexitate

	if req.Email == "" || req.Password == "" || !validatePassword(req.Password) {
		// 4.1: mesaj generic pentru a nu confirma validitatea emailului sau parolei
		http.Error(w, `{"error":"Invalid input"}`, 400)
		return
	}

	// 4.2
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, `{"error":"Server error"}`, 500)
		return
	}
	_, err = db.DB.Exec(
		"INSERT INTO users (email, password) VALUES (?, ?)",
		req.Email, string(hash),
	)
	if err != nil {
		// VULNERABIL: user enumeration
		http.Error(w, `{"error":"Email deja inregistrat"}`, 409)
		return
	}

	db.DB.Exec("INSERT INTO audit_logs (action, ip_address) VALUES (?, ?)",
		"REGISTER", r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Cont creat cu succes"})
}

func Login(w http.ResponseWriter, r *http.Request) {
	var req LoginRequest
	_ = json.NewDecoder(r.Body).Decode(&req)
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))

	invalid := func() {
		// mesaj unic (ajuta si la 4.4)
		http.Error(w, `{"error":"Invalid credentials"}`, http.StatusUnauthorized)
	}

	if req.Email == "" || req.Password == "" {
		invalid()
		return
	}

	var (
		userID       int
		passwordHash string
		failedCount  int
		lockedUntil  sql.NullString
	)

	err := db.DB.QueryRow(
		"SELECT id, password, failed_login_count, locked_until FROM users WHERE email = ?",
		req.Email,
	).Scan(&userID, &passwordHash, &failedCount, &lockedUntil)

	if err != nil {
		// nu dezvaluim daca user exista
		invalid()
		return
	}

	// lockout check
	if lockedUntil.Valid && lockedUntil.String != "" {
		if t, err := time.Parse(time.RFC3339, lockedUntil.String); err == nil {
			if time.Now().UTC().Before(t) {
				_, _ = db.DB.Exec(
					"INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
					userID, "LOGIN_BLOCKED_LOCKED", r.RemoteAddr,
				)
				invalid()
				return
			}
		}
	}

	// bcrypt compare
	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		failedCount++

		var newLocked any = nil
		if failedCount >= maxFailedLogins {
			newLocked = time.Now().UTC().Add(lockoutFor).Format(time.RFC3339)
		}

		_, _ = db.DB.Exec(
			"UPDATE users SET failed_login_count = ?, locked_until = ? WHERE id = ?",
			failedCount, newLocked, userID,
		)

		_, _ = db.DB.Exec(
			"INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
			userID, "LOGIN_FAIL", r.RemoteAddr,
		)

		invalid()
		return
	}

	// success => reset counters
	_, _ = db.DB.Exec("UPDATE users SET failed_login_count = 0, locked_until = NULL WHERE id = ?", userID)

	_, _ = db.DB.Exec(
		"INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
		userID, "LOGIN_SUCCESS", r.RemoteAddr,
	)

	// pentru 4.3 e suficient ca login sa raspunda 200)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"message": "Autentificare reusita"})
}

func Logout(w http.ResponseWriter, r *http.Request) {
	// Sterge cookie-ul - vulnerabil: fara HttpOnly si Secure
	http.SetCookie(w, &http.Cookie{
		Name:    "auth_token",
		Value:   "",
		Path:    "/",
		Expires: time.Unix(0, 0),
	})
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Deconectat"})
}

// Me - returneaza datele utilizatorului logat, vulnerabil: fara validare token, fara expirare token
func Me(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserIDFromRequest(r)
	if err != nil {
		http.Error(w, `{"error":"Neautentificat"}`, 401)
		return
	}

	var email string
	err = db.DB.QueryRow("SELECT email FROM users WHERE id = ?", userID).Scan(&email)
	if err != nil {
		http.Error(w, `{"error":"User invalid"}`, 401)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"user_id": userID,
		"email":   email,
	})
}

// ForgotPassword - genereaza token de reset
func ForgotPassword(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Email string `json:"email"`
	}
	json.NewDecoder(r.Body).Decode(&body)

	var userID int
	err := db.DB.QueryRow("SELECT id FROM users WHERE email = ?", body.Email).Scan(&userID)
	if err != nil {
		// VULNERABIL: mesaj diferit confirmă că emailul NU există
		http.Error(w, `{"error":"Email negasit"}`, 404)
		return
	}

	// VULNERABIL: token = timestamp in secunde — usor de ghicit/brute-forced
	token := fmt.Sprintf("%d", time.Now().Unix())
	db.DB.Exec("INSERT INTO reset_tokens (user_id, token) VALUES (?, ?)", userID, token)

	// token-ul este trimis in raspuns, nu prin email
	// in productie se trimite email — aici il afisam direct
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message":     "Token generat (in productie se trimite pe email)",
		"reset_token": token,
	})
}

// ResetPassword - reseteaza parola folosind token-ul
func ResetPassword(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Token    string `json:"token"`
		Password string `json:"password"`
	}
	json.NewDecoder(r.Body).Decode(&body)

	// 4.1: politica parola + mesaj generic
	if body.Token == "" || body.Password == "" || !validatePassword(body.Password) {
		http.Error(w, `{"error":"Invalid input"}`, 400)
		return
	}

	var userID int
	err := db.DB.QueryRow(
		"SELECT user_id FROM reset_tokens WHERE token = ?", body.Token,
	).Scan(&userID)
	if err != nil {
		http.Error(w, `{"error":"Token invalid"}`, 400)
		return
	}

	// 4.2
	hash, err := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, `{"error":"Server error"}`, 500)
		return
	}

	_, err = db.DB.Exec("UPDATE users SET password = ? WHERE id = ?", string(hash), userID)
	if err != nil {
		http.Error(w, `{"error":"Eroare DB"}`, 500)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Parola resetata"})
}
