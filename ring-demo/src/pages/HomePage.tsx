import { Link } from "react-router-dom";

interface ModeCardProps {
  to: string;
  title: string;
  cta: string;
}

function ModeCard({ to, title, cta }: ModeCardProps) {
  return (
    <Link className="mode-card" to={to}>
      <h2>{title}</h2>
      <span>{cta}</span>
    </Link>
  );
}

export function HomePage() {
  return (
    <main className="home">
      <section className="hero" aria-labelledby="hero-title">
        <p className="eyebrow">EUREKA RING</p>
        <h1 id="hero-title">Intelligence, within reach.</h1>
        <p>Speak an idea. Move through your tools. Feel the result.</p>
        <div
          className="ring-placeholder"
          aria-label="Ring product visual placeholder"
          role="img"
        />
      </section>

      <section className="mode-grid" aria-label="Ring demos">
        <ModeCard to="/flash" title="Flash Mode" cta="Explore Flash" />
        <ModeCard to="/vibe" title="Vibe Mode" cta="Explore Vibe" />
      </section>
    </main>
  );
}
