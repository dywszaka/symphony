defmodule SymphonyWeb.DashboardController do
  use Phoenix.Controller, formats: [:html]

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    case Symphony.Orchestrator.snapshot() do
      {:ok, snapshot} ->
        conn
        |> put_resp_content_type("text/html")
        |> html(render_dashboard(snapshot))

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> put_resp_content_type("text/html")
        |> html(render_unavailable(reason))
    end
  end

  defp render_dashboard(snapshot) do
    running_count = map_size(snapshot.running)
    claimed_count = length(snapshot.claimed)
    completed_count = length(snapshot.completed)
    poll_seconds = div(snapshot.poll_interval_ms, 1_000)
    token_total = snapshot.codex_totals.total_tokens

    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="refresh" content="10">
      #{favicon_link()}
      <title>Symphony Dashboard</title>
      #{styles()}
    </head>
    <body>
      <main class="shell">
        <header class="masthead">
          <div>
            <p class="eyebrow">Orchestration console</p>
            <h1>Symphony</h1>
          </div>
          <div class="status">
            <span class="status-dot"></span>
            System online
          </div>
        </header>

        <section class="metrics" aria-label="Orchestrator counters">
          #{metric("Running", running_count, "Active agent processes")}
          #{metric("Claimed", claimed_count, "Issues reserved for work")}
          #{metric("Completed", completed_count, "Finished issue records")}
          #{metric("Max concurrency", snapshot.max_concurrent_agents, "#{poll_seconds}s poll interval")}
        </section>

        <section class="panel">
          <div>
            <p class="eyebrow">Runtime</p>
            <h2>Orchestrator State</h2>
          </div>
          <dl class="state-grid">
            #{state_item("Poll interval", "#{poll_seconds}s")}
            #{state_item("Retry entries", map_size(snapshot.retry_attempts))}
            #{state_item("Input tokens", snapshot.codex_totals.input_tokens)}
            #{state_item("Output tokens", snapshot.codex_totals.output_tokens)}
            #{state_item("Total tokens", token_total)}
            #{state_item("Seconds running", snapshot.codex_totals.seconds_running)}
          </dl>
        </section>

        <section class="panel compact">
          <div>
            <p class="eyebrow">API</p>
            <h2>Raw State Endpoint</h2>
          </div>
          <a class="link-button" href="/api/v1/state">Open JSON state</a>
        </section>
      </main>
    </body>
    </html>
    """
  end

  defp render_unavailable(reason) do
    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      #{favicon_link()}
      <title>Symphony Unavailable</title>
      #{styles()}
    </head>
    <body>
      <main class="shell">
        <header class="masthead">
          <div>
            <p class="eyebrow">Orchestration console</p>
            <h1>Symphony</h1>
          </div>
          <div class="status down">Service unavailable</div>
        </header>
        <section class="panel">
          <h2>Orchestrator State</h2>
          <p class="muted">#{escape(reason)}</p>
        </section>
      </main>
    </body>
    </html>
    """
  end

  defp metric(label, value, hint) do
    """
    <article class="metric">
      <span>#{label}</span>
      <strong>#{value}</strong>
      <small>#{hint}</small>
    </article>
    """
  end

  defp state_item(label, value) do
    """
    <div>
      <dt>#{label}</dt>
      <dd>#{value}</dd>
    </div>
    """
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp favicon_link do
    """
    <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' fill='%230b6f6b'/%3E%3Cpath d='M16 40c8 8 24 8 32 0M18 24h28M22 32h20' stroke='white' stroke-width='6' stroke-linecap='round' fill='none'/%3E%3C/svg%3E">
    """
  end

  defp styles do
    """
    <style>
      :root {
        color-scheme: light;
        --ink: #111417;
        --muted: #66717d;
        --line: #d8dde2;
        --paper: #f7f4ee;
        --panel: #fffdf8;
        --accent: #0b6f6b;
        --accent-2: #b53b2d;
        --shadow: 0 18px 45px rgba(31, 35, 38, 0.10);
      }

      * { box-sizing: border-box; }

      body {
        margin: 0;
        min-height: 100vh;
        color: var(--ink);
        background:
          linear-gradient(90deg, rgba(17, 20, 23, 0.045) 1px, transparent 1px),
          linear-gradient(0deg, rgba(17, 20, 23, 0.045) 1px, transparent 1px),
          var(--paper);
        background-size: 48px 48px;
        font-family: ui-sans-serif, "Avenir Next", "Segoe UI", sans-serif;
      }

      .shell {
        width: min(1120px, calc(100vw - 32px));
        margin: 0 auto;
        padding: 40px 0;
      }

      .masthead {
        display: flex;
        align-items: end;
        justify-content: space-between;
        gap: 24px;
        margin-bottom: 28px;
      }

      .eyebrow {
        margin: 0 0 8px;
        color: var(--accent-2);
        font-size: 0.75rem;
        font-weight: 800;
        letter-spacing: 0;
        text-transform: uppercase;
      }

      h1, h2 { margin: 0; line-height: 1; }

      h1 {
        font-family: Georgia, "Times New Roman", serif;
        font-size: clamp(3.2rem, 10vw, 7.6rem);
        font-weight: 700;
      }

      h2 {
        font-size: 1.35rem;
      }

      .status {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        min-height: 40px;
        padding: 0 14px;
        border: 1px solid var(--line);
        background: var(--panel);
        box-shadow: var(--shadow);
        font-size: 0.95rem;
        font-weight: 700;
        white-space: nowrap;
      }

      .status.down { color: var(--accent-2); }

      .status-dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: var(--accent);
        box-shadow: 0 0 0 5px rgba(11, 111, 107, 0.15);
      }

      .metrics {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 14px;
        margin-bottom: 14px;
      }

      .metric, .panel {
        border: 1px solid var(--line);
        background: rgba(255, 253, 248, 0.92);
        box-shadow: var(--shadow);
      }

      .metric {
        min-height: 150px;
        padding: 18px;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
      }

      .metric span, dt {
        color: var(--muted);
        font-size: 0.86rem;
        font-weight: 800;
      }

      .metric strong {
        font-size: 3.4rem;
        line-height: 1;
      }

      .metric small {
        color: var(--muted);
        font-size: 0.82rem;
      }

      .panel {
        margin-top: 14px;
        padding: 22px;
      }

      .panel.compact {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 18px;
      }

      .state-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 1px;
        margin: 20px 0 0;
        background: var(--line);
        border: 1px solid var(--line);
      }

      .state-grid div {
        min-height: 86px;
        padding: 16px;
        background: var(--panel);
      }

      dt, dd { margin: 0; }

      dd {
        margin-top: 10px;
        font-size: 1.65rem;
        font-weight: 800;
      }

      .link-button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 42px;
        padding: 0 16px;
        border: 1px solid var(--accent);
        color: white;
        background: var(--accent);
        text-decoration: none;
        font-weight: 800;
      }

      .muted { color: var(--muted); }

      @media (max-width: 780px) {
        .shell { width: min(100vw - 24px, 680px); padding: 24px 0; }
        .masthead { align-items: start; flex-direction: column; }
        .metrics, .state-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
        .panel.compact { align-items: start; flex-direction: column; }
      }

      @media (max-width: 480px) {
        .metrics, .state-grid { grid-template-columns: 1fr; }
        .metric { min-height: 128px; }
      }
    </style>
    """
  end
end
