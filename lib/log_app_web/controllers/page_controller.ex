defmodule LogAppWeb.PageController do
  use LogAppWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
