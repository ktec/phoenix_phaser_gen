#!/bin/bash
## Usage: phaser [options] ARG1
##
## Options:
##   -h, --help    Display this message.
##   -n            Dry-run; only show what would be done.
##


project=${1:-"Tracker"}
lobby_channel=${2:-"games:lobby"}
play_channel=${2:-"games:play"}



# curl https://github.com/ktec/phoenixphaserdemo/compare/01_synchronised_text...02_uuid_user_token.patch | patch -p1

# sed -i -e '1s/.*/shit/g' README.md
# sed -e $'5i\\\n\   {:ok, socket}' games_channel.ex
# Need a good way to only replace if its not already there...
# position='5i';
# string='  channel "$lobby_channel", $project.GamesChannel';
# sed -e "$position\|$string|h; \${x;s|$string||;{g;t};a\\" -e "$string" -e "}" file

if [ ! -d "web/static/vendor/js/phaser" ]; then
  mkdir -p web/static/vendor/js/phaser
  curl -L -o web/static/vendor/js/phaser/phaser.min.js https://raw.githubusercontent.com/photonstorm/phaser/master/v2-community/build/phaser.min.js
  curl -L -o web/static/vendor/js/phaser/phaser.map https://github.com/photonstorm/phaser/raw/master/v2-community/build/phaser.map
  echo Phaser installed!
fi

cat >web/static/js/Game.js <<EOL
import {Lobby} from "./states/Lobby"
import {joinChannel} from "./common/channels"

export class Game extends Phaser.Game {
  constructor(width, height, container) {
    super(width, height, Phaser.AUTO, container, null)

    this.state.add("lobby", Lobby, false)
  }

  start(socket) {
    socket.connect()

    // create and join the lobby channel
    const channel = socket.channel("$lobby_channel", {})

    joinChannel(channel, () => {
      console.log("Joined successfully")
      // start the lobby [name, clearWorld, clearCache, ...stateInits]
      this.state.start("lobby", true, false, channel)
    })
  }
}
EOL

cat >web/static/js/app.js <<EOL
// Import dependencies
import {Game} from "./Game"
import {Socket} from "phoenix"

const socket = new Socket("/socket", {})
const game = new Game(700, 450, "phaser")

// Lets go!
game.start(socket)
EOL

cat >web/templates/page/index.html.eex <<EOL
<div id="phaser"></div>
EOL

mkdir -p web/static/js/states
mkdir -p web/static/js/common

cat >web/static/js/states/Lobby.js <<EOL
import { createLabel } from "../common/labels"
import { syncPosition } from "../common/sync"

export class Lobby extends Phaser.State {
  init(...args) {
    const [channel] = args
    this.channel = channel
  }

  create() {
    const label = createLabel(this, "Hello world")
    label.anchor.setTo(0.5)
    label.inputEnabled = true
    label.input.enableDrag()

    // send message on drag stop [sprite, channel, event]
    syncPosition(label, this.channel, label.events.onDragUpdate)
  }
}
EOL

cat >web/static/js/common/labels.js <<EOL
const DEFAULT_STYLE = {font: "65px Arial", fill: "#ffffff" }

// createLabel :: State -> String -> Object -> Sprite
export const createLabel = (state, message, style = DEFAULT_STYLE) => {

  const {centerX, centerY} = state.world
  return state.add.text(centerX, centerY, message, style)

}
EOL

cat >web/static/js/common/channels.js <<EOL
// joinChannel :: Channel -> Channel
export const joinChannel = (channel, success, failure, timeout) => {
  channel
    .join()
    .receive("ok", success || joinOk)
    .receive("error", failure || joinError)
    .receive("timeout", timeout || joinTimeout)
  return channel
}

// joinOk :: Response -> Console
const joinOk = (response) => console.log(\`Joined successfully\`, response)

// joinError :: Response -> Console
const joinError = (response) => console.log(\`Failed to join channel\`, response)

// joinError :: Null -> Console
const joinTimeout = () => console.log("Networking issue. Still waiting...")
EOL

cat >web/static/js/common/sync.js <<EOL
// syncPosition :: Sprite -> Channel -> Event -> Function -> Event -> Event
export const syncPosition = (sprite, channel, event) => {
  event.add(sprite => sendPosition(sprite, channel))
  receivePosition(sprite, channel)
}

// sendPosition :: Sprite -> Channel -> String
export const sendPosition = (sprite, channel) => {
  const message = serializePosition(sprite)
  console.log("Sending message", message)
  channel.push("position", message)
}

// serializePosition :: Sprite -> Object
export const serializePosition = ({x, y}) => Object.assign({x, y})

// receivePosition = Sprite -> Channel -> Push
export const receivePosition = (sprite, channel) => {
  const callback = (message) => {
    console.log("Received message", message)
    const {x,y} = message
    sprite.position.setTo(x, y)
  }
  channel.on("position", callback)
}
EOL

cat > web/channels/lobby_channel.ex <<EOL
defmodule $project.LobbyChannel do
  use $project.Web, :channel

  def join("$lobby_channel", payload, socket) do
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("position", payload, socket) do
    broadcast_from socket, "position", payload
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(_payload) do
    true
  end
end
EOL

patch -p1 <<EOL
diff --git a/web/channels/user_socket.ex b/web/channels/user_socket.ex
--- a/web/channels/user_socket.ex
+++ b/web/channels/user_socket.ex
@@ -3,6 +3,7 @@ defmodule $project.UserSocket do

   ## Channels
   # channel "room:*", $project.RoomChannel
+  channel "$lobby_channel", $project.LobbyChannel

   ## Transports
   transport :websocket, Phoenix.Transports.WebSocket
EOL

patch -p1 <<EOL
diff --git a/mix.exs b/mix.exs
--- a/mix.exs
+++ b/mix.exs
@@ -33,6 +33,7 @@ defmodule $project.Mixfile do
      {:phoenix_html, "~> 2.6"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:gettext, "~> 0.11"},
-     {:cowboy, "~> 1.0"}]
+     {:cowboy, "~> 1.0"},
+     {:uuid, "~> 1.1"}]
   end
 end
EOL

mix deps.get
# patch -p1 <<EOL
# diff --git a/mix.lock b/mix.lock
# --- a/mix.lock
# +++ b/mix.lock
# @@ -14,4 +14,5 @@
#    "poison": {:hex, :poison, "1.5.2"},
#    "poolboy": {:hex, :poolboy, "1.5.1"},
#    "postgrex": {:hex, :postgrex, "0.11.1"},
# -  "ranch": {:hex, :ranch, "1.2.1"}}
# +  "ranch": {:hex, :ranch, "1.2.1"},
# +  "uuid": {:hex, :uuid, "1.1.3"}}
# EOL

patch -p1 <<EOL
diff --git a/web/channels/user_socket.ex b/web/channels/user_socket.ex
--- a/web/channels/user_socket.ex
+++ b/web/channels/user_socket.ex
@@ -20,9 +20,15 @@ defmodule $project.UserSocket do
   #
   # See \`Phoenix.Token\` documentation for examples in
   # performing token verification on connect.
-  def connect(_params, socket) do
-    {:ok, socket}
+  def connect(%{"token" => token}, socket) do
+    auth = Phoenix.Token.verify(socket, "token", token)
+    case auth do
+      {:ok, verified_user_id} ->
+        {:ok, assign(socket, :user_id, verified_user_id)}
+      {:error, _} -> :error
+    end
   end
+  def connect(_params, _socket), do: :error

   # Socket id's are topics that allow you to identify all sockets for a given user:
   #
EOL

patch -p1 <<EOL
diff --git a/web/controllers/page_controller.ex b/web/controllers/page_controller.ex
--- a/web/controllers/page_controller.ex
+++ b/web/controllers/page_controller.ex
@@ -1,7 +1,22 @@
 defmodule $project.PageController do
   use $project.Web, :controller
+  alias $project.Endpoint
+
+  def session_uuid(conn) do
+    case get_session(conn, :player_uuid) do
+      nil ->
+        uuid = UUID.uuid4
+        put_session(conn, :player_uuid, uuid)
+        uuid
+      existent_uuid -> existent_uuid
+    end
+  end
+
+  def token(conn) do
+    Phoenix.Token.sign(Endpoint, "token", session_uuid(conn))
+  end

   def index(conn, _params) do
-    render conn, "index.html"
+    render conn, "index.html", %{token: token(conn)}
   end
 end
EOL

patch -p1 <<EOL
diff --git a/web/static/js/app.js b/web/static/js/app.js
--- a/web/static/js/app.js
+++ b/web/static/js/app.js
@@ -11,7 +11,11 @@
 import {Game} from "./Game"
 import {Socket} from "phoenix"

-const socket = new Socket("/socket", {})
+const token = document.head.querySelector("[name=token]").content
+const socket = new Socket("/socket", {
+  params: {token: token},
+  // logger: (kind, msg, data) => { console.log(\`${kind}: ${msg}\`, data) }
+})
 const game = new Game(700, 450, "phaser")

 // Lets go!
EOL

patch -p1 <<EOL
diff --git a/web/templates/layout/app.html.eex b/web/templates/layout/app.html.eex
--- a/web/templates/layout/app.html.eex
+++ b/web/templates/layout/app.html.eex
@@ -6,6 +6,7 @@
     <meta name="viewport" content="width=device-width, initial-scale=1">
     <meta name="description" content="">
     <meta name="author" content="">
+    <%= tag(:meta, name: "token", content: @token) %>

     <title>Hello Demo!</title>
     <link rel="stylesheet" href="<%= static_path(@conn, "/css/app.css") %>">
EOL

patch -p1 <<EOL
diff --git a/web/channels/lobby_channel.ex b/web/channels/lobby_channel.ex
--- a/web/channels/lobby_channel.ex
+++ b/web/channels/lobby_channel.ex
@@ -1,12 +1,19 @@
 defmodule $project.LobbyChannel do
   use $project.Web, :channel
+  require Logger

   def join("$lobby_channel", payload, socket) do
     if authorized?(payload) do
+      Logger.debug "#{socket.assigns.user_id} joined the Lobby channel"
       {:ok, socket}
     else
       {:error, %{reason: "unauthorized"}}
     end
   end

+  def terminate(_reason, socket) do
+    Logger.debug "#{socket.assigns.user_id} left the Lobby channel"
+    socket
+  end
+
   # broadcast position data to everyone else
   def handle_in("position", payload, socket) do
     broadcast_from socket, "position", payload
EOL

patch -p1 <<EOL
diff --git a/web/channels/play_channel.ex b/web/channels/play_channel.ex
new file mode 100644
--- /dev/null
+++ b/web/channels/play_channel.ex
@@ -0,0 +1,36 @@
+defmodule $project.PlayChannel do
+  use $project.Web, :channel
+  require Logger
+
+  def join("$play_channel", payload, socket) do
+    if authorized?(payload) do
+      Logger.debug "#{socket.assigns.user_id} joined the Play channel"
+      {:ok, socket}
+    else
+      {:error, %{reason: "unauthorized"}}
+    end
+  end
+
+  def terminate(_reason, socket) do
+    Logger.debug "#{socket.assigns.user_id} left the Play channel"
+    socket
+  end
+
+  # It is also common to receive messages from the client and
+  # broadcast to everyone in the current topic (lobby).
+  def handle_in("shout", payload, socket) do
+    broadcast socket, "shout", payload
+    {:noreply, socket}
+  end
+
+  # broadcast position data to everyone else
+  def handle_in("position", payload, socket) do
+    broadcast_from socket, "position", payload
+    {:noreply, socket}
+  end
+
+  # Add authorization logic here as required.
+  defp authorized?(_payload) do
+    true
+  end
+end
EOL

patch -p1 <<EOL
diff --git a/web/channels/user_socket.ex b/web/channels/user_socket.ex
--- a/web/channels/user_socket.ex
+++ b/web/channels/user_socket.ex
@@ -4,6 +4,7 @@ defmodule $project.UserSocket do
   ## Channels
   # channel "rooms:*", $project.RoomChannel
   channel "$lobby_channel", $project.LobbyChannel
+  channel "$play_channel", $project.PlayChannel

   ## Transports
   transport :websocket, Phoenix.Transports.WebSocket
EOL

patch -p1 <<EOL
diff --git a/web/static/js/Game.js b/web/static/js/Game.js
--- a/web/static/js/Game.js
+++ b/web/static/js/Game.js
@@ -1,21 +1,45 @@
 import {Lobby} from "./states/Lobby"
+import {Play} from "./states/Play"
 import {joinChannel} from "./common/channels"

 export class Game extends Phaser.Game {
   constructor(width, height, container) {
     super(width, height, Phaser.AUTO, container, null)

     this.state.add("lobby", Lobby, false)
+    this.state.add("play", Play, false)
   }

   start(socket) {
+    console.log("GAME STARTING")
     socket.connect()
+    console.log(socket)

-    // create and join the lobby channel
-    const channel = socket.channel("$lobby_channel", {})
+    // set up channels
+    this.gotoLobby = () => {
+      console.log("create Lobby channel")
+      const channel = socket.channel("$lobby_channel", {})

-    joinChannel(channel, () => {
-      console.log("Joined successfully")
-      // start the lobby [name, clearWorld, clearCache, ...stateInits]
-      this.state.start("lobby", true, false, channel)
-    })
+      console.log("join Lobby channel")
+      joinChannel(channel, () => {
+
+        console.log("successfully joined Lobby channel")
+        this.state.start("lobby", true, false, channel)
+
+      })
+    }
+
+    this.gotoPlay = () => {
+      console.log("create Play channel")
+      const channel = socket.channel("$play_channel", {})
+
+      console.log("join Play channel")
+      joinChannel(channel, () => {
+
+        console.log("successfully joined Play channel")
+        this.state.start("play", true, false, channel)
+
+      })
+    }
+
+    this.gotoLobby()
   }
 }
EOL

patch -p1 <<EOL
diff --git a/web/static/js/app.js b/web/static/js/app.js
--- a/web/static/js/app.js
+++ b/web/static/js/app.js
@@ -12,10 +12,7 @@ import {Game} from "./Game"
 import {Socket} from "phoenix"

 const token = document.head.querySelector("[name=token]").content
-const socket = new Socket("/socket", {
-  params: {token: token},
-  // logger: (kind, msg, data) => { console.log(\`${kind}: ${msg}\`, data) }
-})
+const socket = new Socket("/socket", { params: {token: token} })
 const game = new Game(700, 450, "phaser")

 // Lets go!
EOL

patch -p1 < ../phoenix_phaser_gen/patch_test.patch


patch -p1 <<EOL
diff --git a/lib/tracker.ex b/lib/tracker.ex
--- a/lib/tracker.ex
+++ b/lib/tracker.ex
@@ -13,6 +13,7 @@ defmodule Tracker do
       supervisor($project.Repo, []),
       # Here you could define other workers and supervisors as children
       # worker($project.Worker, [arg1, arg2, arg3]),
+      supervisor($project.PlayerSupervisor, []),
     ]

     # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html

diff --git a/lib/tracker/game.ex b/lib/tracker/game.ex
new file mode 100644
--- /dev/null
+++ b/lib/tracker/game.ex
@@ -0,0 +1,20 @@
+defmodule $project.Game do
+  use GenServer
+  alias $project.{Endpoint, Player, PlayerSupervisor}
+
+  def join(user_id) do
+    PlayerSupervisor.start(user_id)
+    sprites = PlayerSupervisor.get_all
+    {:ok, %{id: user_id, sprites: sprites}}
+  end
+
+  def leave(user_id) do
+    Endpoint.broadcast!("$play_channel", "player:leave", %{id: user_id, type: :player})
+    PlayerSupervisor.stop(user_id)
+  end
+
+  def update_position(user_id, %{"x" => x, "y" => y}) do
+    pid = :global.whereis_name(user_id)
+    Player.update_position(pid, %{x: x, y: y})
+  end
+end
diff --git a/lib/tracker/player.ex b/lib/tracker/player.ex
new file mode 100644
--- /dev/null
+++ b/lib/tracker/player.ex
@@ -0,0 +1,47 @@
+defmodule $project.Player do
+  use GenServer
+  alias $project.{Endpoint, Randomise}
+
+  defmodule State do
+    defstruct id: nil,
+              position: %{x: 0, y: 0},
+              type: "square"
+  end
+
+  ### PUBLIC API ###
+
+  def inspect(pid) do
+    GenServer.call(pid, :inspect)
+  end
+
+  def set_position(process, position) do
+    GenServer.call(process, {:set_position, position})
+  end
+
+  def start_link([id]) do
+    state = %State{id: id,
+                   position: random_position()}
+    GenServer.start_link(__MODULE__, state, [name: {:global, id}])
+  end
+
+  ### GENSERVER CALLBACKS ###
+
+  def init(state) do
+    Endpoint.broadcast!("$play_channel", "player:join", state)
+    {:ok, state}
+  end
+
+  def handle_call(:inspect, _from, state) do
+    {:reply, state, state}
+  end
+
+  def handle_call({:set_position, position}, from, state) do
+    Endpoint.broadcast_from!(from, "$play_channel", "player:update", state)
+    {:reply, :ok, %{state | position: position}}
+  end
+
+  defp random_position(width \\\ 800, height \\\ 600) do
+    %{x: Randomise.random(width),
+      y: Randomise.random(height)}
+  end
+end
diff --git a/lib/tracker/player_supervisor.ex b/lib/tracker/player_supervisor.ex
new file mode 100644
--- /dev/null
+++ b/lib/tracker/player_supervisor.ex
@@ -0,0 +1,29 @@
+defmodule $project.PlayerSupervisor do
+  alias $project.Player
+
+  def start_link do
+    import Supervisor.Spec, warn: false
+    children = [
+      worker(Player, [], [restart: :transient])
+    ]
+    opts = [strategy: :simple_one_for_one, max_restart: 0, name: __MODULE__]
+    Supervisor.start_link(children, opts)
+  end
+
+  def start(id) do
+    Supervisor.start_child(__MODULE__, [[id]])
+  end
+
+  def stop(id) do
+    pid = :global.whereis_name(id)
+    Supervisor.terminate_child(__MODULE__, pid)
+    # Player.stop(pid)
+  end
+
+  def get_all do
+    Supervisor.which_children(__MODULE__)
+    |> Enum.map(&inspect_state(&1))
+  end
+
+  defp inspect_state({_, pid, _, _}), do: Player.inspect(pid)
+end
diff --git a/lib/tracker/randomise.ex b/lib/tracker/randomise.ex
new file mode 100644
--- /dev/null
+++ b/lib/tracker/randomise.ex
@@ -0,0 +1,14 @@
+defmodule $project.Randomise do
+  @on_load :reseed_generator
+
+  def reseed_generator do
+    {_, sec, micro} = :os.timestamp()
+    hash = :erlang.phash2({self(), make_ref()})
+    :random.seed(hash, sec, micro)
+    :ok
+  end
+
+  def random(number) do
+    :random.uniform(number)
+  end
+end
diff --git a/web/channels/play_channel.ex b/web/channels/play_channel.ex
--- a/web/channels/play_channel.ex
+++ b/web/channels/play_channel.ex
@@ -1,11 +1,17 @@
 defmodule $project.PlayChannel do
   use $project.Web, :channel
+  alias $project.Game
   require Logger

   def join("$play_channel", payload, socket) do
     if authorized?(payload) do
       Logger.debug "#{socket.assigns.user_id} joined the Play channel"
-      {:ok, socket}
+      case Game.join(socket.assigns.user_id) do
+        {:ok, response} ->
+          {:ok, response, socket}
+        error ->
+          error
+      end
     else
       {:error, %{reason: "unauthorized"}}
     end
@@ -13,6 +19,7 @@ defmodule $project.PlayChannel do

   def terminate(_reason, socket) do
     Logger.debug "#{socket.assigns.user_id} left the Play channel"
+    Game.leave(socket.assigns.user_id)
     socket
   end
EOL
