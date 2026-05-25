defmodule WaxxWeb.Api.V1.TemplateTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures
  import Waxx.KanbanFixtures

  alias Waxx.Workflows

  defp setup_user do
    user = confirmed_user_fixture()
    %{user: user, token: api_token_fixture(user)}
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "templates CRUD" do
    test "create + list + show", %{conn: conn} do
      %{token: token} = setup_user()

      created =
        conn
        |> auth(token)
        |> post(~p"/api/v1/workflow_templates", %{name: "Bug triage"})

      assert %{"template" => %{"id" => tid, "name" => "Bug triage"}} = json_response(created, 201)

      listing = build_conn() |> auth(token) |> get(~p"/api/v1/workflow_templates")
      assert %{"templates" => list} = json_response(listing, 200)
      assert Enum.any?(list, &(&1["id"] == tid))

      detail = build_conn() |> auth(token) |> get(~p"/api/v1/workflow_templates/#{tid}")
      assert %{"template" => t} = json_response(detail, 200)
      assert t["stages"] == []
    end

    test "update + delete", %{conn: conn} do
      %{user: user, token: token} = setup_user()
      template = template_fixture(user)

      updated =
        conn
        |> auth(token)
        |> patch(~p"/api/v1/workflow_templates/#{template.id}", %{name: "Renamed"})

      assert %{"template" => %{"name" => "Renamed"}} = json_response(updated, 200)

      deleted =
        build_conn() |> auth(token) |> delete(~p"/api/v1/workflow_templates/#{template.id}")

      assert response(deleted, 204) == ""
      refute Workflows.get_template(template.id)
    end
  end

  describe "stages" do
    test "add + update + delete a stage", %{conn: conn} do
      %{user: user, token: token} = setup_user()
      template = template_fixture(user)

      added =
        conn
        |> auth(token)
        |> post(~p"/api/v1/workflow_templates/#{template.id}/stages", %{
          name: "Triage",
          color: "#888888"
        })

      assert %{"stage" => stage} = json_response(added, 201)
      assert stage["name"] == "Triage"

      renamed =
        build_conn()
        |> auth(token)
        |> patch(~p"/api/v1/template_stages/#{stage["id"]}", %{name: "Reviewing"})

      assert %{"stage" => %{"name" => "Reviewing"}} = json_response(renamed, 200)

      deleted = build_conn() |> auth(token) |> delete(~p"/api/v1/template_stages/#{stage["id"]}")
      assert response(deleted, 204) == ""
    end
  end

  describe "transitions" do
    test "add + delete a transition", %{conn: conn} do
      %{user: user, token: token} = setup_user()
      # Fresh template with no pre-existing transitions.
      {:ok, template} = Workflows.create_template(user, %{"name" => "T", "description" => ""})
      {:ok, todo} = Workflows.add_stage(template, %{"name" => "Todo"})
      {:ok, done} = Workflows.add_stage(template, %{"name" => "Done"})

      added =
        conn
        |> auth(token)
        |> post(~p"/api/v1/workflow_templates/#{template.id}/transitions", %{
          from_stage_id: todo.id,
          to_stage_id: done.id,
          label: "complete"
        })

      assert %{"transition" => t} = json_response(added, 201)
      assert t["from_stage_id"] == todo.id
      assert t["label"] == "complete"

      deleted =
        build_conn() |> auth(token) |> delete(~p"/api/v1/template_transitions/#{t["id"]}")

      assert response(deleted, 204) == ""
    end
  end

  describe "labels" do
    test "add + delete a label", %{conn: conn} do
      %{user: user, token: token} = setup_user()
      template = template_fixture(user)

      added =
        conn
        |> auth(token)
        |> post(~p"/api/v1/workflow_templates/#{template.id}/labels", %{
          name: "bug",
          color: "#ff0000"
        })

      assert %{"label" => l} = json_response(added, 201)
      assert l["name"] == "bug"

      deleted = build_conn() |> auth(token) |> delete(~p"/api/v1/template_labels/#{l["id"]}")
      assert response(deleted, 204) == ""
    end
  end

  describe "fields" do
    test "add + update + delete a field", %{conn: conn} do
      %{user: user, token: token} = setup_user()
      template = template_fixture(user)

      added =
        conn
        |> auth(token)
        |> post(~p"/api/v1/workflow_templates/#{template.id}/fields", %{
          name: "owner",
          kind: "text"
        })

      assert %{"field" => f} = json_response(added, 201)
      assert f["name"] == "owner"

      updated =
        build_conn()
        |> auth(token)
        |> patch(~p"/api/v1/template_fields/#{f["id"]}", %{show_on_card: true})

      assert %{"field" => %{"show_on_card" => true}} = json_response(updated, 200)

      deleted = build_conn() |> auth(token) |> delete(~p"/api/v1/template_fields/#{f["id"]}")
      assert response(deleted, 204) == ""
    end
  end

  describe "POST /api/v1/boards (create from template)" do
    test "creates a board cloned from a template", %{conn: conn} do
      %{user: user, token: token} = setup_user()
      template = template_fixture(user)

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards", %{template_id: template.id, name: "Sprint 7"})

      assert %{"board" => b} = json_response(conn, 201)
      assert b["name"] == "Sprint 7"
      assert b["role"] == "owner"
    end

    test "validation_failed without template_id", %{conn: conn} do
      %{token: token} = setup_user()
      conn = conn |> auth(token) |> post(~p"/api/v1/boards", %{name: "X"})
      assert json_response(conn, 422)
    end
  end
end
