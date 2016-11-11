#!/bin/bash

if [ ! -d "web/static/vendor/js/phaser" ]; then
  mkdir -p web/static/vendor/js/phaser
  curl -L -o web/static/vendor/js/phaser/phaser.min.js https://raw.githubusercontent.com/photonstorm/phaser/master/build/phaser.min.js
  curl -L -o web/static/vendor/js/phaser/phaser.map https://raw.githubusercontent.com/photonstorm/phaser/master/build/phaser.map
  echo Phaser installed!
fi

cat >web/static/js/Game.js <<EOL
import {joinChannel} from "./common/channels"
import {Lobby} from "./states/Lobby"

export class Game extends Phaser.Game {
  constructor(width, height, container) {
    super(width, height, Phaser.AUTO, container, null)

    this.state.add("lobby", Lobby, false)
  }

  start(socket) {
    socket.connect()

    // create and join the lobby channel
    const channel = socket.channel("games:lobby", {})

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

export class Lobby extends Phaser.State {
  init(...args) {
    const [channel] = args
    this.channel = channel
  }

  create() {
    const label = createLabel(this, "Hello world", this.channel)
    label.anchor.setTo(0.5)
    label.inputEnabled = true
    label.input.enableDrag()

    // send message on drag stop [sprite, channel, event]
    syncPosition(label, this.channel, this.label.events.onDragStop)
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
const joinOk = (response) => console.log(`Joined successfully`, response)

// joinError :: Response -> Console
const joinError = (response) => console.log(`Failed to join channel`, response)

// joinError :: Null -> Console
const joinTimeout = () => console.log("Networking issue. Still waiting...")
EOL

cat >web/static/js/common/sync.js <<EOL
// syncPosition :: Sprite -> Channel -> Event -> Function -> Event -> Event
export const syncPosition = (sprite, channel, event) => {
  event.add(sprite => sendPosition(sprite, channel))
}

// sendPosition :: Sprite -> Channel -> String
export const sendPosition = (sprite, channel) => {
  console.log(serializePosition(sprite))
}

// serializePosition :: Sprite -> Object
export const serializePosition = ({x, y}) => Object.assign({x, y})
EOL

cat > web/channels/games_channel.ex <<EOL
defmodule Tracker.GamesChannel do
  use Tracker.Web, :channel

  def join("games:lobby", payload, socket) do
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("shout", payload, socket) do
    broadcast socket, "shout", payload
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(_payload) do
    true
  end
end
EOL

ed web/channels/user_socket.ex << END
5i
  channel "games:lobby", Tracker.GamesChannel
.
w
q
END
