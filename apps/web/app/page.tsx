import { redirect } from 'next/navigation'

// The landing page moves in later; until then the game is the site.
export default function Home() {
  redirect('/play')
}
