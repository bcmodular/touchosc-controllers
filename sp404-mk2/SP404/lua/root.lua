local abletonPushHandler = root:findByName('ableton_push_handler', true)

function onReceiveMIDI(message, connections)

  --print('onReceiveMIDI')
  --print('\t message     =', unpack(message))
  --print('\t connections =', unpack(connections))

  if connections[2] then
    abletonPushHandler:notify('midi_message', message)
  end
end
