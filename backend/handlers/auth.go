package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"Break-the-Login/backend/db"

	"github.com/golang-jwt/jwt/v5"
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

// Login fara rate limiting, vulnerabil la brute-force, mesaje diferite pentru erori
func Login(w http.ResponseWriter, r *http.Request) {
	var req LoginRequest
	json.NewDecoder(r.Body).Decode(&req)

	// Cauta userul in baza de date
	var userID int
	var storedPassword string
	err := db.DB.QueryRow(
		"SELECT id, password FROM users WHERE email = ?", req.Email,
	).Scan(&userID, &storedPassword)
	if err != nil {
		http.Error(w, `{"error":"Utilizatorul nu exista"}`, 401)
		return
	}

	// 4.2
	err = bcrypt.CompareHashAndPassword([]byte(storedPassword), []byte(req.Password))
	if err != nil {
		// parola greșită (sau hash invalid)
		http.Error(w, `{"error":"Invalid credentials"}`, 401)
		return
	}

	// Generare token JWT - vulnerabil: fara expirare, fara refresh token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"user_id": userID,
		"email":   req.Email,
		// fara expirare
	})
	tokenString, err := token.SignedString(jwtSecret)

	// VULNERABIL: cookie fără HttpOnly și Secure
	http.SetCookie(w, &http.Cookie{
		Name:  "auth_token",
		Value: tokenString,
		Path:  "/",
		// HttpOnly: true,  <- lipsa, XSS poate fura cookie-ul
		// Secure: true,    <- lipsa, trimis si pe HTTP
		// SameSite: http.SameSiteStrictMode, <- lipsa
	})

	db.DB.Exec("INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
		userID, "LOGIN", r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message": "Autentificare reusita",
		"token":   tokenString,
	})
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
