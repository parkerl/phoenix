defmodule Phoenix.Controller do
  import Plug.Conn
  alias Plug.Conn.AlreadySentError

  require Logger

  @unsent [:unset, :set]

  @moduledoc """
  Controllers are used to group common functionality in the same
  (pluggable) module.

  For example, the route:

      get "/users/:id", MyApp.UserController, :show

  will invoke the `show/2` action in the `MyApp.UserController`:

      defmodule MyApp.UserController do
        use MyApp.Web, :controller

        plug :action

        def show(conn, %{"id" => id}) do
          user = Repo.get(User, id)
          render conn, "show.html", user: user
        end
      end

  An action is just a regular function that receives the connection
  and the request parameters as arguments. The connection is a
  `Plug.Conn` struct, as specified by the Plug library.

  ## Connection

  A controller by default provides many convenience functions for
  manipulating the connection, rendering templates, and more.

  Those functions are imported from two modules:

    * `Plug.Conn` - a bunch of low-level functions to work with
      the connection

    * `Phoenix.Controller` - functions provided by Phoenix
      to support rendering, and other Phoenix specific behaviour

  ## Rendering and layouts

  One of the main features provided by controllers is the ability
  to do content negotiation and render templates based on
  information sent by the client. Read `render/3` to learn more.

  It is also important to not confuse `Phoenix.Controller.render/3`
  with `Phoenix.View.render/3` in the long term. The former expects
  a connection and relies on content negotiation while the latter is
  connection-agnostic and typically invoked from your views.

  ## Plug pipeline

  As routers, controllers also have their own plug pipeline. However,
  different from routers, controllers have a single pipeline:

      defmodule MyApp.UserController do
        use MyApp.Web, :controller

        plug :authenticate, usernames: ["jose", "eric", "sonny"]
        plug :action

        def show(conn, params) do
          # authenticated users only
        end

        defp authenticate(conn, options) do
          if get_session(conn, :username) in options[:usernames] do
            conn
          else
            conn |> redirect(Router.root_path) |> halt
          end
        end
      end

  The `:action` plug must always be invoked and it represents the action
  to be dispatched to.

  Check `Phoenix.Controller.Pipeline` for more information on `plug/2`
  and how to customize the plug pipeline.

  ## Options

  When used, the controller supports the following options:

    * `:namespace` - sets the namespace to properly inflect
      the layout view. By default it uses the base alias
      in your controller name.
  """
  defmacro __using__(opts) do
    quote do
      import Plug.Conn
      import Phoenix.Controller

      use Phoenix.Controller.Pipeline

      plug Phoenix.Controller.Logger
      plug :put_new_layout, {Phoenix.Controller.__layout__(__MODULE__, unquote(opts)), :application}
      plug :put_new_view, Phoenix.Controller.__view__(__MODULE__)
    end
  end

  @doc """
  Returns the action name as an atom, raises if unavailable.
  """
  @spec action_name(Plug.Conn.t) :: atom
  def action_name(conn), do: conn.private.phoenix_action

  @doc """
  Returns the controller module as an atom, raises if unavailable.
  """
  @spec controller_module(Plug.Conn.t) :: atom
  def controller_module(conn), do: conn.private.phoenix_controller

  @doc """
  Returns the router module as an atom, raises if unavailable.
  """
  @spec router_module(Plug.Conn.t) :: atom
  def router_module(conn), do: conn.private.phoenix_router

  @doc """
  Returns the endpoint module as an atom, raises if unavailable.
  """
  @spec endpoint_module(Plug.Conn.t) :: atom
  def endpoint_module(conn), do: conn.private.phoenix_endpoint

  @doc """
  Sends JSON response.

  It uses the configured `:format_encoders` under the `:phoenix`
  application for `:json` to pick up the encoder module.

  ## Examples

      iex> json conn, %{id: 123}

  """
  @spec json(Plug.Conn.t, term) :: Plug.Conn.t
  def json(conn, data) do
    encoder =
      Application.get_env(:phoenix, :format_encoders)
      |> Keyword.get(:json, Poison)

    send_resp(conn, conn.status || 200, "application/json", encoder.encode_to_iodata!(data))
  end

  @doc """
  Sends text response.

  ## Examples

      iex> text conn, "hello"

      iex> text conn, :implements_to_string

  """
  @spec text(Plug.Conn.t, String.Chars.t) :: Plug.Conn.t
  def text(conn, data) do
    send_resp(conn, conn.status || 200, "text/plain", to_string(data))
  end

  @doc """
  Sends html response.

  ## Examples

      iex> html conn, "<html><head>..."

  """
  @spec html(Plug.Conn.t, iodata) :: Plug.Conn.t
  def html(conn, data) do
    send_resp(conn, conn.status || 200, "text/html", data)
  end

  @doc """
  Sends redirect response to the given url.

  For security, `:to` only accepts paths. Use the `:external`
  option to redirect to any URL.

  ## Examples

      iex> redirect conn, to: "/login"

      iex> redirect conn, external: "http://elixir-lang.org"

  """
  def redirect(conn, opts) when is_list(opts) do
    url  = url(opts)
    {:safe, html} = Phoenix.HTML.html_escape(url)
    body = "<html><body>You are being <a href=\"#{html}\">redirected</a>.</body></html>"

    conn
    |> put_resp_header("location", url)
    |> send_resp(conn.status || 302, "text/html", body)
  end

  defp url(opts) do
    cond do
      to = opts[:to] ->
        case to do
          "/" <> _ -> to
          _        -> raise ArgumentError, "the :to option in redirect expects a path"
        end
      external = opts[:external] ->
        external
      true ->
        raise ArgumentError, "expected :to or :external option in redirect/2"
    end
  end

  @doc """
  Stores the view for rendering.

  Raises `Plug.Conn.AlreadySentError` if the conn was already sent.
  """
  @spec put_view(Plug.Conn.t, atom) :: Plug.Conn.t
  def put_view(%Plug.Conn{state: state} = conn, module) when state in @unsent do
    put_private(conn, :phoenix_view, module)
  end

  def put_view(_conn, _module), do: raise AlreadySentError

  @doc """
  Stores the view for rendering if one was not stored yet.

  Raises `Plug.Conn.AlreadySentError` if the conn was already sent.
  """
  @spec put_new_view(Plug.Conn.t, atom) :: Plug.Conn.t
  def put_new_view(%Plug.Conn{state: state} = conn, module)
      when state in @unsent do
    update_in conn.private, &Map.put_new(&1, :phoenix_view, module)
  end

  def put_new_view(_conn, _module) do
    raise Plug.Conn.AlreadySentError
  end

  @doc """
  Retrieves the current view.
  """
  @spec view_module(Plug.Conn.t) :: atom
  def view_module(conn) do
    conn.private.phoenix_view
  end

  @doc """
  Stores the layout for rendering.

  The layout must be a tuple, specifying the layout view and the layout
  name, or false. In case a previous layout is set, `put_layout` also
  accepts the layout name to be given as a string or as an atom. If a
  string, it must contain the format. Passing an atom means the layout
  format will be found at rendering time, similar to the template in
  `render/3`.

  ## Examples

      iex> layout(conn)
      false

      iex> conn = put_layout conn, {AppView, "application"}
      iex> layout(conn)
      {AppView, "application"}

      iex> conn = put_layout conn, "print"
      iex> layout(conn)
      {AppView, "print"}

      iex> conn = put_layout :print
      iex> layout(conn)
      {AppView, :print}

  Raises `Plug.Conn.AlreadySentError` if the conn was already sent.
  """
  @spec put_layout(Plug.Conn.t, {atom, binary} | binary | false) :: Plug.Conn.t
  def put_layout(%Plug.Conn{state: state} = conn, layout) do
    if state in @unsent do
      _put_layout(conn, layout)
    else
      raise Plug.Conn.AlreadySentError
    end
  end

  def _put_layout(conn, layout)

  def _put_layout(conn, false) do
    put_private(conn, :phoenix_layout, false)
  end

  def _put_layout(conn, {mod, layout}) when is_atom(mod) do
    put_private(conn, :phoenix_layout, {mod, layout})
  end

  def _put_layout(conn, layout) when is_binary(layout) or is_atom(layout) do
    update_in conn.private, fn private ->
      case Map.get(private, :phoenix_layout, false) do
        {mod, _} -> Map.put(private, :phoenix_layout, {mod, layout})
        false    -> raise "cannot use put_layout/2 with atom/binary when layout is false, use a tuple instead"
      end
    end
  end

  @doc """
  Stores the layout for rendering if one was not stored yet.

  Raises `Plug.Conn.AlreadySentError` if the conn was already sent.
  """
  @spec put_new_layout(Plug.Conn.t, {atom, binary} | false) :: Plug.Conn.t
  def put_new_layout(%Plug.Conn{state: state} = conn, layout)
      when (is_tuple(layout) and tuple_size(layout) == 2) or layout == false do
    if state in @unsent do
      update_in conn.private, &Map.put_new(&1, :phoenix_layout, layout)
    else
      raise AlreadySentError
    end
  end

  @doc """
  Sets which formats have a layout when rendering.

  ## Examples

      iex> layout_formats conn
      ["html"]

      iex> put_layout_formats conn, ["html", "mobile"]
      iex> layout_formats conn
      ["html", "mobile"]

  Raises `Plug.Conn.AlreadySentError` if the conn was already sent.
  """
  @spec put_layout_formats(Plug.Conn.t, [String.t]) :: Plug.Conn.t
  def put_layout_formats(%Plug.Conn{state: state} = conn, formats)
      when state in @unsent and is_list(formats) do
    put_private(conn, :phoenix_layout_formats, formats)
  end

  def put_layout_formats(_conn, _formats) do
    raise Plug.Conn.AlreadySentError
  end

  @doc """
  Retrieves current layout formats.
  """
  @spec layout_formats(Plug.Conn.t) :: [String.t]
  def layout_formats(conn) do
    Map.get(conn.private, :phoenix_layout_formats, ~w(html))
  end

  @doc """
  Retrieves the current layout.
  """
  @spec layout(Plug.Conn.t) :: {atom, String.t} | false
  def layout(conn), do: conn.private |> Map.get(:phoenix_layout, false)

  @doc """
  Render the given template or the default template
  specified by the current action with the given assigns.

  See `render/3` for more information.
  """
  @spec render(Plug.Conn.t, Dict.t | binary | atom) :: Plug.Conn.t
  def render(conn, template_or_assigns \\ [])

  def render(conn, template) when is_binary(template) or is_atom(template) do
    render(conn, template, [])
  end

  def render(conn, assigns) do
    render(conn, action_name(conn), assigns)
  end

  @doc """
  Renders the given `template` and `assigns` based on the `conn` information.

  Once the template is rendered, the template format is set as the response
  content type (for example, an HTML template will set "text/html" as response
  content type) and the data is sent to the client with default status of 200.

  ## Arguments

    * `conn` - the `Plug.Conn` struct

    * `template` - which may be an atom or a string. If an atom, like `:index`,
      it will render a template with the same format as the one found in
      `conn.params["format"]`. For example, for an HTML request, it will render
      the "index.html" template. If the template is a string, it must contain
      the extension too, like "index.json"

    * `assigns` - a dictionary with the assigns to be used in the view. Those
      assigns are merged and have higher precedence than the connection assigns
      (`conn.assigns`)

  ## Examples

      defmodule MyApp.UserController do
        use Phoenix.Controller

        plug :action

        def show(conn, _params) do
          render conn, "show.html", message: "Hello"
        end
      end

  The example above renders a template "show.html" from the `MyApp.UserView`
  and sets the response content type to "text/html".

  In many cases, you may want the template format to be set dynamically based
  on the request. To do so, you can pass the template name as an atom (without
  the extension):

      def show(conn, _params) do
        render conn, :show, message: "Hello"
      end

  In order for the example above to work, we need to do content negotiation with
  the accepts plug before rendering. You can do so by adding the following to your
  pipeline (in the router):

      plug :accepts, ["html"]

  ## Views

  By default, Controllers render templates in a view with a similar name to the
  controller. For example, `MyApp.UserController` will render templates inside
  the `MyApp.UserView`. This information can be changed any time by using
  `render/3`, `render/4` or the `put_view/2` function:

      def show(conn, _params) do
        render(conn, MyApp.SpecialView, :show, message: "Hello")
      end

      def show(conn, _params) do
        conn
        |> put_view(MyApp.SpecialView)
        |> render(:show, message: "Hello")
      end

  `put_view/2` can also be used as a plug:

      defmodule MyApp.UserController do
        use Phoenix.Controller

        plug :put_view, MyApp.SpecialView
        plug :action

        def show(conn, _params) do
          render conn, :show, message: "Hello"
        end
      end

  ## Layouts

  Templates are often rendered inside layouts. By default, Phoenix
  will render layouts for html requests. For example:

      defmodule MyApp.UserController do
        use Phoenix.Controller

        plug :action

        def show(conn, _params) do
          render conn, "show.html", message: "Hello"
        end
      end

  will render the  "show.html" template inside an "application.html"
  template specified in `MyApp.LayoutView`. `put_layout/2` can be used
  to change the layout, similar to how `put_view/2` can be used to change
  the view.

  `layout_formats/2` and `put_layout_formats/2` can be used to configure
  which formats support/require layout rendering (defaults to "html" only).
  """
  @spec render(Plug.Conn.t, binary | atom, Dict.t) :: Plug.Conn.t
  @spec render(Plug.Conn.t, module, binary | atom) :: Plug.Conn.t
  def render(conn, template, assigns)
    when is_atom(template) and is_list(assigns) do
    format =
      conn.params["format"] ||
      raise "cannot render template #{inspect template} because conn.params[\"format\"] is not set. " <>
            "Please set `plug :accepts, %w(html json ...)` in your pipeline."
    do_render(conn, template_name(template, format), format, assigns)
  end

  def render(conn, template, assigns) when is_binary(template) do
    case Path.extname(template) do
      "." <> format ->
        do_render(conn, template, format, assigns)
      "" ->
        raise "cannot render template #{inspect template} without format. Use an atom if the " <>
              "template format is meant to be set dynamically based on the request format"
    end
  end

  def render(conn, view, template)
    when is_atom(view) and is_binary(template) or is_atom(template) do
    render(conn, view, template, [])
  end

  @spec render(Plug.Conn.t, atom, atom | binary, Dict.t) :: Plug.Conn.t
  def render(conn, view, template, assigns)
    when is_atom(view) and is_binary(template) or is_atom(template) do
    conn
    |> put_view(view)
    |> render(template, assigns)
  end

  defp do_render(conn, template, format, assigns) do
    assigns = to_map(assigns)
    content_type = Plug.MIME.type(format)
    conn = prepare_assigns(conn, assigns, format)
    view = Map.get(conn.private, :phoenix_view) ||
            raise "a view module was not specified, set one with put_view/2"
    data = Phoenix.View.render_to_iodata(view, template,
                                         Map.put(conn.assigns, :conn, conn))
    send_resp(conn, conn.status || 200, content_type, data)
  end

  @doc """
  Scrubs the parameters from the request.

  This process is two-fold:

    * Checks to see if the `required_key` is present
    * Changes empty parameters of `required_key` (recursively) to nils

  This function is useful to remove empty strings sent
  via HTML forms. If you are providing an API, there
  is likely no need to invoke `scrub_params/2`.

  If the `required_key` is not present, it will
  raise `Phoenix.MissingParamError`.

  ## Examples

      iex> scrub_params(conn, "user")

  """
  @spec scrub_params(Plug.Conn.t, [String.t]) :: Plug.Conn.t
  def scrub_params(conn, required_key) when is_binary(required_key) do
    param = Map.get(conn.params, required_key) |> scrub_param()

    unless param do
      raise Phoenix.MissingParamError, key: required_key
    end

    params = Map.put(conn.params, required_key, param)
    %{conn | params: params}
  end

  defp scrub_param(%{__struct__: mod} = struct) when is_atom(mod) do
    struct
  end
  defp scrub_param(%{} = param) do
    Enum.reduce(param, %{}, fn({k, v}, acc) ->
      Map.put(acc, k, scrub_param(v))
    end)
  end
  defp scrub_param(param) when is_list(param) do
    Enum.map(param, &scrub_param/1)
  end
  defp scrub_param(param) do
    if scrub?(param), do: nil, else: param
  end

  defp scrub?(" " <> rest), do: scrub?(rest)
  defp scrub?(""), do: true
  defp scrub?(_), do: false

  defp prepare_assigns(conn, assigns, format) do
    layout =
      case layout(conn, assigns, format) do
        {mod, layout} -> {mod, template_name(layout, format)}
        false -> false
      end

    update_in conn.assigns,
              & &1 |> Map.merge(assigns) |> Map.put(:layout, layout)
  end

  defp layout(conn, assigns, format) do
    if format in layout_formats(conn) do
      case Map.fetch(assigns, :layout) do
        {:ok, layout} -> layout
        :error -> layout(conn)
      end
    else
      false
    end
  end

  defp to_map(assigns) when is_map(assigns), do: assigns
  defp to_map(assigns) when is_list(assigns), do: :maps.from_list(assigns)
  defp to_map(assigns), do: Dict.merge(%{}, assigns)

  defp template_name(name, format) when is_atom(name), do:
    Atom.to_string(name) <> "." <> format
  defp template_name(name, _format) when is_binary(name), do:
    name

  defp send_resp(conn, default_status, default_content_type, body) do
    conn
    |> ensure_resp_content_type(default_content_type)
    |> send_resp(conn.status || default_status, body)
  end

  defp ensure_resp_content_type(%{resp_headers: resp_headers} = conn, content_type) do
    if List.keyfind(resp_headers, "content-type", 0) do
      conn
    else
      content_type = content_type <> "; charset=utf-8"
      %{conn | resp_headers: [{"content-type", content_type}|resp_headers]}
    end
  end

  @doc """
  Enables CSRF protection.

  Currently used as a wrapper function for `Plug.CSRFProtection`
  and mainly serves as a function plug in `YourApp.Router`.

  Check `get_csrf_token/0` and `delete_csrf_token/0` for
  retrieving and deleting CSRF tokens.
  """
  def protect_from_forgery(conn, opts \\ []) do
    Plug.CSRFProtection.call(conn, opts)
  end

  @doc """
  Gets the CSRF token.
  """
  defdelegate get_csrf_token(), to: Plug.CSRFProtection

  @doc """
  Deletes any CSRF token set.
  """
  defdelegate delete_csrf_token(), to: Plug.CSRFProtection

  @doc """
  Performs content negotiation based on the available formats.

  It receives a connection, a list of formats that the server
  is capable of rendering and then proceeds to perform content
  negotiation based on the request information. If the client
  accepts any of the given formats, the request proceeds.

  If the request contains a "format" parameter, it is
  considered to be the format desired by the client. If no
  "format" parameter is available, this function will parse
  the "accept" header and find a matching format accordingly.

  It is important to notice that browsers have historically
  sent bad accept headers. For this reason, this function will
  default to "html" format whenever:

    * the accepted list of arguments contains the "html" format

    * the accept header specified more than one media type preceeded
      or followed by the wildcard media type "*/*"

  This function raises `Phoenix.NotAcceptableError`, which is rendered
  with status 406, whenever the server cannot serve a response in any
  of the formats expected by the client.

  ## Examples

  `accepts/2` can be invoked as a function:

      iex> accepts(conn, ["html", "json"])

  or used as a plug:

      plug :accepts, ["html", "json"]
      plug :accepts, ~w(html json)

  """
  @spec accepts(Plug.Conn.t, [binary]) :: Plug.Conn.t | no_return
  def accepts(conn, [_|_] = accepted) do
    case Map.fetch conn.params, "format" do
      {:ok, format} ->
        handle_params_accept(conn, format, accepted)
      :error ->
        handle_header_accept(conn, get_req_header(conn, "accept"), accepted)
    end
  end

  defp handle_params_accept(conn, format, accepted) do
    if format in accepted do
      conn
    else
      Logger.debug "Unknown format #{inspect format} in plug :accepts, " <>
                   "expected one of #{inspect accepted}"
      conn |> send_resp(406, "") |> halt()
    end
  end

  # In case there is no accept header or the header is */*
  # we use the first format specified in the accepts list.
  defp handle_header_accept(conn, header, [first|_]) when header == [] or header == ["*/*"] do
    accept(conn, first)
  end

  # In case there is a header, we need to parse it.
  # But before we check for */* because if one exists and we serve html,
  # we unfortunately need to assume it is a browser sending us a request.
  defp handle_header_accept(conn, [header|_], accepted) do
    if header =~ "*/*" and "html" in accepted do
      accept(conn, "html")
    else
      parse_header_accept(conn, String.split(header, ","), [], accepted)
    end
  end

  defp parse_header_accept(conn, [h|t], acc, accepted) do
    case Plug.Conn.Utils.media_type(h) do
      {:ok, type, subtype, args} ->
        exts = parse_exts(type <> "/" <> subtype)
        q    = parse_q(args)

        if q === 1.0 && (format = find_format(exts, accepted)) do
          accept(conn, format)
        else
          parse_header_accept(conn, t, [{-q, exts}|acc], accepted)
        end
      :error ->
        parse_header_accept(conn, t, acc, accepted)
    end
  end

  defp parse_header_accept(conn, [], acc, accepted) do
    acc
    |> Enum.sort()
    |> Enum.find_value(&parse_header_accept(conn, &1, accepted))
    |> Kernel.||(refuse(conn, accepted))
  end

  defp parse_header_accept(conn, {_, exts}, accepted) do
    if format = find_format(exts, accepted) do
      accept(conn, format)
    end
  end

  defp parse_q(args) do
    case Map.fetch(args, "q") do
      {:ok, float} ->
        case Float.parse(float) do
          {float, _} -> float
          :error -> 1.0
        end
      :error ->
        1.0
    end
  end

  defp parse_exts("*/*" = type), do: type
  defp parse_exts(type),         do: Plug.MIME.extensions(type)

  defp find_format("*/*", accepted), do: Enum.fetch!(accepted, 0)
  defp find_format(exts, accepted),  do: Enum.find(exts, &(&1 in accepted))

  defp accept(conn, format) do
    put_in conn.params["format"], format
  end

  defp refuse(conn, accepted) do
    Logger.debug "No supported media type in accept header in plug :accepts, " <>
                 "expected one of #{inspect accepted}"
    conn |> send_resp(406, "") |> halt()
  end

  @doc """
  Fetches the flash storage.
  """
  def fetch_flash(conn, _opts \\ []) do
    flash = get_session(conn, "phoenix_flash") || %{}
    conn  = persist_flash(conn, flash)

    register_before_send conn, fn conn ->
      flash = conn.private.phoenix_flash

      cond do
        map_size(flash) == 0 ->
          conn
        conn.status in 300..308 ->
          put_session(conn, "phoenix_flash", flash)
        true ->
          delete_session(conn, "phoenix_flash")
      end
    end
  end

  @doc """
  Persists a value in flash.

  Returns the updated connection.

  ## Examples

      iex> conn = put_flash(conn, :notice, "Welcome Back!")
      iex> get_flash(conn, :notice)
      "Welcome Back!"

  """
  def put_flash(conn, key, message) do
    persist_flash(conn, Map.put(get_flash(conn), flash_key(key), message))
  end

  @doc """
  Returns a previously set flash message or nil.

  ## Examples

      iex> conn = put_flash(conn, :notice, "Welcome Back!")
      iex> get_flash(conn)
      %{"notice" => "Welcome Back!"}

  """
  def get_flash(conn) do
    Map.get(conn.private, :phoenix_flash) ||
      raise ArgumentError, message: "flash not fetched, call fetch_flash/2"
  end

  @doc """
  Returns a message from flash by key

  ## Examples

      iex> conn = put_flash(conn, :notice, "Welcome Back!")
      iex> get_flash(conn, :notice)
      "Welcome Back!"

  """
  def get_flash(conn, key) do
    get_flash(conn)[flash_key(key)]
  end

  @doc """
  Clears all flash messages.
  """
  def clear_flash(conn) do
    persist_flash(conn, %{})
  end

  defp flash_key(binary) when is_binary(binary), do: binary
  defp flash_key(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp persist_flash(conn, value) do
    put_private(conn, :phoenix_flash, value)
  end

  @doc false
  def __view__(controller_module) do
    controller_module
    |> Phoenix.Naming.unsuffix("Controller")
    |> Kernel.<>("View")
    |> String.to_atom()
  end

  @doc false
  def __layout__(controller_module, opts) do
    namespace =
      if given = Keyword.get(opts, :namespace) do
        given
      else
        controller_module
        |> Atom.to_string()
        |> String.split(".")
        |> Enum.drop(-1)
        |> Enum.take(2)
        |> Module.concat()
      end
    Module.concat(namespace, "LayoutView")
  end
end
