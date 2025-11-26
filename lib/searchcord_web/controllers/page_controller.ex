defmodule SearchcordWeb.PageController do
  use SearchcordWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
