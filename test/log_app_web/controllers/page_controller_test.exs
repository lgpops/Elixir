defmodule LogAppWeb.PageControllerTest do
  use LogAppWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Log Dashboard"
  end
end
