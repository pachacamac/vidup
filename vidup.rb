require 'busker'
require 'em-websocket'

module EventMachine
  module WebSocket
    class Connection < EventMachine::Connection
      def remote_ip
        get_peername[2,6].unpack('nC4')[1..4].join('.')
      end
    end
  end
end

Thread.new {
  @ws_clients = []
  EM.run do
    EM::WebSocket.run(:host => "0.0.0.0", :port => 8008) do |ws|
      ws.onopen do |handshake|
        puts "WebSocket connection opened from #{ws.remote_ip}"
        @ws_clients << ws
      end

      ws.onclose do
        puts "WebSocket connection closed"
        @ws_clients.delete(ws)
      end

      ws.onmessage do |msg|
        puts "WebSocket received message '#{msg}'"
        @ws_clients.each{|e| e.send(msg) if e != ws}
      end
    end
  end
}

Busker::Busker.new(:port => 8000) do
  route '/' do
    render :main
  end
end.start

__END__
@@ main
<!DOCTYPE html>
<html>
  <head>
    <title>WebRTC P2P Videochat</title>
    <style>
      body{ background: #333; }
      @keyframes blinker { from { opacity: 1; } to { opacity: 0; }}
      @-webkit-keyframes blinker { from { opacity: 1; } to { opacity: 0; }}
      #notice { color: white; margin-left: 23%;
        animation: blinker 1s cubic-bezier(.5, 0, 1, 1) infinite alternate;
        -webkit-animation: blinker 1s cubic-bezier(.5, 0, 1, 1) infinite alternate; }
      #video { width: 640px; height: 480px; position: absolute; top:0; bottom: 0; left: 0; right: 0; margin: auto; }
      #remote-video { width: 640px; height: 480px; }
      #local-video { left: 0; top: 0; position: absolute; z-index: 1; width: 160px; height: 120px; }
      .mirror { -webkit-transform:scaleX(-1); -moz-transform:scaleX(-1); transform:scaleX(-1); }
    </style>
  </head>
  <body>
    <h2 id="notice">&#x21e7; Please allow this &#x21e7;</h2>
    <div id="video" class="ceterflex">
      <video id="remote-video" autoplay="true" controls="true"></video>
      <video id="local-video" class="mirror" autoplay="true" controls="true" muted="true"></video>
    </div>
    <script>
      /* MIT License: https://webrtc-experiment.appspot.com/licence/ */
      /* 2013, Muaz Khan<muazkh>--[github.com/muaz-khan] */
      /* Demo & Documentation: http://bit.ly/RTCPeerConnection-Documentation */
      window.moz = !! navigator.mozGetUserMedia;
      var PeerConnection = function (options) {
          var PeerConnection = window.mozRTCPeerConnection || window.webkitRTCPeerConnection,
              SessionDescription = window.mozRTCSessionDescription || window.RTCSessionDescription,
              IceCandidate = window.mozRTCIceCandidate || window.RTCIceCandidate;

          // See https://gist.github.com/zziuni/3741933 for a list of public STUN servers
          var iceServers = { iceServers: [{url: 'stun:stun.stunprotocol.org'}, {url: 'stun:stunserver.org'},
                                          {url: 'stun:stun.l.google.com:19302'}, {url: 'stun:stun.schlund.de'},
                                          {url: 'turn:numb.viagenie.ca', credential: 'muazkh', username: 'webrtc@live.com'},
                                          {url: 'turn:192.158.29.39:3478?transport=udp', credential: 'JZEOEt2V3Qb0y27GRntt2u2PAYA=', username: '28224511:1379330808'},
                                          {url: 'turn:192.158.29.39:3478?transport=tcp', credential: 'JZEOEt2V3Qb0y27GRntt2u2PAYA=', username: '28224511:1379330808'}]};

          var optional = { optional: [] };
          // See http://www.webrtc.org/interop under "Constraints / configurations issues."
          if (!moz) optional.optional = [{ DtlsSrtpKeyAgreement: true }];

          var peerConnection = new PeerConnection(iceServers, optional);
          peerConnection.onicecandidate = function(event) {
              if (!event.candidate) return;
              options.onicecandidate(event.candidate);
          }
          peerConnection.onaddstream = function(event) {
              console.log('------------onaddstream');
              options.onaddstream(event.stream);
          }

          var constraints = options.constraints || {
              optional: [],
              mandatory: { OfferToReceiveAudio: true, OfferToReceiveVideo: true }
          };
          if (moz) constraints.mandatory.MozDontOfferDataChannel = true;

          return {
              createOffer: function (callback) {
                  peerConnection.createOffer(function (sessionDescription) {
                      peerConnection.setLocalDescription(sessionDescription);
                      callback(sessionDescription);
                  }, null, constraints);
              },

              createAnswer: function (offerSDP, callback) {
                  peerConnection.setRemoteDescription(new SessionDescription(offerSDP));
                  peerConnection.createAnswer(function (sessionDescription) {
                      peerConnection.setLocalDescription(sessionDescription);
                      callback(sessionDescription);
                  }, null, constraints);
              },

              setRemoteDescription: function (sdp) {
                  console.log('--------adding answer sdp:');
                  console.log(sdp.sdp);
                  sdp = new SessionDescription(sdp);
                  peerConnection.setRemoteDescription(sdp);
              },

              addICECandidate: function (candidate) {
                  console.log("addICE: got candidate: " + candidate.candidate);
                  peerConnection.addIceCandidate(new IceCandidate({
                              sdpMLineIndex: candidate.sdpMLineIndex,
                              candidate: candidate.candidate
                          }));
              },

              addStream: function(stream) {
                  console.log("stream provided, attaching...");
                  peerConnection.addStream(stream);
              }
          };
      };
    </script>
    <script>
      /* MIT License: https://webrtc-experiment.appspot.com/licence/ */
      var call = function (config) {
          var wsAddr = 'ws://'+document.location.hostname;
          var port = config.wsPort || document.location.port;
          if(port) wsAddr += ':'+port;
          var peerConnection = PeerConnection(makePeerConfig()), webSocket = new WebSocket(wsAddr+'/');
          // configure the signalling WebSocket
          webSocket.onmessage = function (event) {
              console.log("received a message: " + event.data);
              onIncomingMessage(JSON.parse(event.data));
          };
          webSocket.push = webSocket.send;
          webSocket.send = function (data) { webSocket.push(JSON.stringify(data)); };
          function onIncomingMessage(response) {
              // the other client has sent me an offer SDP
              if (response.offerSDP) {
                  console.log("received offerSDP " + response.offerSDP + ", will answer");
                  peerConnection.addStream(config.localStream);
                  peerConnection.createAnswer(response.offerSDP, function (sdp) {
                      console.log("sending answer SDP");
                      webSocket.send({ answerSDP: sdp });
                  });
              }
              // the other client has sent me an answer SDP
              if (response.answerSDP) { peerConnection.setRemoteDescription(response.answerSDP); }
              // the other client has sent me an ICE candidate
              if (response.candidate) {
                  console.log("got a candidate message, passing to RTCPeerConnection");
                  peerConnection.addICECandidate({
                      sdpMLineIndex: response.candidate.sdpMLineIndex,
                      candidate: response.candidate.candidate
                  });
              }
          }

          // PeerConnection.js's options structure
          function makePeerConfig() {
              return {
                  onicecandidate: function (candidate) {
                      console.log("onICE");
                      webSocket.send({
                          candidate: {
                              sdpMLineIndex: candidate.sdpMLineIndex,
                              candidate: candidate.candidate
                          }
                      });
                  },
                  onaddstream: function (stream) {
                      console.log("onRemoteStream");
                      config.video['src'] = URL.createObjectURL(stream);
                      clearInterval(callInterval); //TODO: is this a good place?
                  }
              };
          }

          return {
              initiateCall: function(localStream) {
                  peerConnection.addStream(localStream); // attach the stream to the peer connection
                  // create the offer SDP and send it when it's ready
                  peerConnection.createOffer(function (sdp) {
                      console.log("sending offer SDP");
                      webSocket.send({ offerSDP: sdp })
                  });
              }
          };
      };
    </script>
    <script>
      navigator.getUserMedia = navigator.webkitGetUserMedia || navigator.mozGetUserMedia;
      var config = { video: document.getElementById('remote-video'), wsPort: 8008 };
      var callPeer = call(config);
      var callInterval = null;
      navigator.getUserMedia({ audio: true, video: true },
          function (localStream) {
              video = document.getElementById('local-video');
              video['src'] = URL.createObjectURL(localStream);
              config.localStream = localStream;
              callInterval = setInterval(function(){ callPeer.initiateCall(config.localStream) }, 1000);
              document.getElementById('notice').style.display = 'none';
          },
          function (e) { console.error(e); }
      );
    </script>
  </body>
</html>
