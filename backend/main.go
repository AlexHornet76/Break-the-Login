package main

import (
	"log"
	"net/http"

	"Break-the-Login/backend/db"
	"Break-the-Login/backend/handlers"

	"github.com/rs/cors"
)

func main() {
	// Initializare baza de date
	db.Init()

	// Rute
	mux := http.NewServeMux()

	mux.HandleFunc("POST /api/register", handlers.Register)
	mux.HandleFunc("POST /api/login", handlers.Login)
	mux.HandleFunc("POST /api/logout", handlers.Logout)
	mux.HandleFunc("GET /api/me", handlers.Me)
	mux.HandleFunc("POST /api/forgot-password", handlers.ForgotPassword)
	mux.HandleFunc("POST /api/reset-password", handlers.ResetPassword)

	// CORS - vulnerabil: AllowAll - nu restrictioneaza originile
	c := cors.New(cors.Options{
		AllowedOrigins:   []string{"http://localhost:5173"},
		AllowedMethods:   []string{"GET", "POST", "OPTIONS"},
		AllowedHeaders:   []string{"Content-Type", "Authorization"},
		AllowCredentials: true,
	})
	handler := c.Handler(mux)

	log.Println("Server pornit pe http://localhost:8080")
	log.Fatal(http.ListenAndServe(":8080", handler))
}
