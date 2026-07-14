import { Link, Route, Routes } from "react-router-dom";

import { HomePage } from "../pages/HomePage";

function PlaceholderPage({ title }: { title: string }) {
  return (
    <main className="placeholder-page">
      <p className="eyebrow">EUREKA RING</p>
      <h1>{title}</h1>
      <p>This demo will be available here.</p>
      <Link to="/">Back home</Link>
    </main>
  );
}

export function App() {
  return (
    <Routes>
      <Route path="/" element={<HomePage />} />
      <Route path="/setup" element={<PlaceholderPage title="Setup" />} />
      <Route path="/flash" element={<PlaceholderPage title="Flash Mode" />} />
      <Route path="/vibe" element={<PlaceholderPage title="Vibe Mode" />} />
    </Routes>
  );
}
