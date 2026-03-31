import axios from 'axios';

// Baza URL a backend-ului Go
const API = axios.create({
  baseURL: 'http://localhost:8080/api',
  withCredentials: true, // trimite cookie-urile automat
})

export const register = (email, password) =>
  API.post('/register', { email, password })

export const login = (email, password) =>
  API.post('/login', { email, password })

export const logout = () =>
  API.post('/logout')

export const getMe = () =>
  API.get('/me')

export const forgotPassword = (email) =>
  API.post('/forgot-password', { email })

export const resetPassword = (token, password) =>
  API.post('/reset-password', { token, password })