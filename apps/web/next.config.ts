import type { NextConfig } from 'next'

const dev = process.env.NODE_ENV !== 'production'

// 'unsafe-inline' scripts and styles are what Next's static pages need without nonces.
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${dev ? " 'unsafe-eval'" : ''}`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "font-src 'self'",
  "connect-src 'self' ws: wss:",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join('; ')

// The Godot export inside /play's frame: it compiles WebAssembly, and JavaScriptBridge.eval
// (town_client.gd reads ?server=) needs 'unsafe-eval'. Only our own /play may frame it.
const godotCsp = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "connect-src 'self' ws: wss: data: blob:",
  "worker-src 'self' blob:",
  "media-src 'self' blob:",
  "object-src 'none'",
  "frame-ancestors 'self'",
].join('; ')

const config: NextConfig = {
  poweredByHeader: false,
  // The dev server refuses pages opened as http://127.0.0.1 (not localhost) unless that host is listed.
  allowedDevOrigins: ['127.0.0.1'],
  async headers() {
    return [
      { source: '/:path*', headers: [{ key: 'Content-Security-Policy', value: csp }] },
      // Later rules win for the same header.
      { source: '/godot/:path*', headers: [{ key: 'Content-Security-Policy', value: godotCsp }] },
      // The export's files keep their names between builds, so revalidate (a 304 once cached) rather than cache blind.
      { source: '/godot/:path*', headers: [{ key: 'Cache-Control', value: 'no-cache' }] },
    ]
  },
}

export default config
