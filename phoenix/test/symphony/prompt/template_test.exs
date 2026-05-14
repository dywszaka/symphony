defmodule Symphony.Prompt.TemplateTest do
  use ExUnit.Case, async: true

  alias Symphony.Prompt.Template
  alias Symphony.Tracker.Issue

  test "renders issue fields and attempt values strictly" do
    issue = %Issue{
      identifier: "MT-42",
      title: "Ship runner",
      labels: ["backend", "runner"],
      created_at: ~U[2026-05-14 00:00:00Z]
    }

    template =
      "Ticket {{ issue.identifier }} {{ issue.title }} labels={{ issue.labels }} attempt={{ attempt }} created={{ issue.created_at }}"

    assert {:ok, rendered} = Template.render(template, issue, attempt: 2)

    assert rendered ==
             "Ticket MT-42 Ship runner labels=backend, runner attempt=2 created=2026-05-14T00:00:00Z"
  end

  test "uses default prompt for blank templates" do
    issue = %Issue{identifier: "MT-1"}

    assert {:ok, "You are working on an issue from Linear."} = Template.render("  ", issue, [])
  end

  test "returns template_render_error for unknown variables and filters" do
    issue = %Issue{identifier: "MT-1"}

    assert {:error, {:template_render_error, {:unknown_variable, "issue.missing"}}} =
             Template.render("{{ issue.missing }}", issue, [])

    assert {:error, {:template_render_error, {:unknown_filter, "upcase"}}} =
             Template.render("{{ issue.identifier | upcase }}", issue, [])
  end
end
