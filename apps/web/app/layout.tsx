import type { Metadata } from 'next'
import type { ReactNode } from 'react'
import './globals.css'

export const metadata: Metadata = {
  title: 'Dhaniverse',
  // TODO: the real icon, once a brand-mark file is copied into this repo. `data:,` stops the browser asking for /favicon.ico.
  icons: { icon: 'data:,' },
}

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
