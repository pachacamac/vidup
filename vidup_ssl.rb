require 'sinatra'
require 'sinatra-websocket'
require 'thin'

$logger = Logger.new(STDERR)
$logger.level = Logger::INFO

set server: 'thin', bind: '127.0.0.1', port: 7777
set namespaces: {}

get '/:namespace?/?' do
  $logger.info("REQUEST NS:#{params[:namespace]}, WS?:#{request.websocket? ? 'Y' : 'N'}")
  if request.websocket?
    request.websocket do |socket|
      client_id = Digest::MD5.hexdigest(socket.hash.to_s)
      namespace = "#{params[:namespace]}"

      socket.onopen do
        $logger.info("CONNECTED #{namespace}/#{client_id}")
        begin
          settings.namespaces[namespace] ||= {}
          settings.namespaces[namespace][client_id] = socket
        rescue
          $logger.error("#{$!} - #{$@.join("\n")}")
        end
      end

      socket.onclose do
        $logger.info("DISCONNECTED\t#{namespace}/#{client_id}")
        begin
          settings.namespaces[namespace].delete(client_id)
          settings.namespaces.delete(namespace) if settings.namespaces[namespace].empty?
        rescue
          $logger.error("#{$!} - #{$@.join("\n")}")
        end
      end

      socket.onmessage do |msg|
        $logger.info("MESSAGE\t#{namespace}/#{client_id} : #{msg}")
        EM.next_tick do
          begin
            settings.namespaces[namespace].each{|k,v| v.send(msg) if k != client_id}
          rescue
            $logger.error("#{$!} - #{$@.join("\n")}")
          end
        end
      end

    end
  else
    erb :main
  end
end

__END__
@@ main
<!DOCTYPE html>
<html>
  <head>
    <title>Vidup - WebRTC P2P Videochat</title>
    <style>
      body{ background: #333; overflow: hidden; }
      * { margin: 0; padding: 0; box-sizing: border-box; }
      @keyframes blinker { from { opacity: 1; } to { opacity: 0; }}
      @-webkit-keyframes blinker { from { opacity: 1; } to { opacity: 0; }}
      #notice { color: white; margin-left: 23%; z-index: 20; position: absolute;
        animation: blinker 1s cubic-bezier(.5, 0, 1, 1) infinite alternate;
        -webkit-animation: blinker 1s cubic-bezier(.5, 0, 1, 1) infinite alternate; }
      #video { height: 100vh; width: 100vw; position: absolute; top: 0; bottom: 0; left: 0; right: 0; margin: auto; }
      .big-video { height: 100%; }
      .small-video { left: 0; top: 0; position: absolute; z-index: 10; height: 20vh; }
      .split-video { height: 50vh; width: 100vw; position: relative; display: block; }
      .mirror { -webkit-transform:scaleX(-1); -moz-transform:scaleX(-1); transform:scaleX(-1); }
    </style>
  </head>
  <body>
    <h2 id="notice">&#x21e7; Please allow this &#x21e7;</h2>
    <div id="video" class="ceterflex">
      <video id="remote-video" class="split-video" autoplay="true" controls="true"></video>
      <video id="local-video" class="split-video mirror" autoplay="true" controls="true" muted="true"></video>
    </div>
    <script>
      /* MIT License: https://webrtc-experiment.appspot.com/licence/ */
      /* 2013, Muaz Khan<muazkh>--[github.com/muaz-khan] */
      /* Demo & Documentation: http://bit.ly/RTCPeerConnection-Documentation */
      window.moz = !! navigator.mozGetUserMedia;
      var PeerConnection = function (options) {
          var PeerConnection = window.mozRTCPeerConnection || window.webkitRTCPeerConnection || window.RTCPeerConnection,
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
          peerConnection.onicecandidate = function(event) { if(event.candidate){ options.onicecandidate(event.candidate) } }
          peerConnection.onaddstream = function(event) { console.log('onaddstream'); options.onaddstream(event.stream) }

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
                  }, function(e){console.log(e)}, constraints);
              },
              createAnswer: function (offerSDP, callback) {
                  peerConnection.setRemoteDescription(new SessionDescription(offerSDP));
                  peerConnection.createAnswer(function (sessionDescription) {
                      peerConnection.setLocalDescription(sessionDescription);
                      callback(sessionDescription);
                  }, function(e){console.log(e)}, constraints);
              },
              setRemoteDescription: function (sdp) {
                  console.log('adding answer sdp:', sdp.sdp);
                  sdp = new SessionDescription(sdp);
                  peerConnection.setRemoteDescription(sdp);
              },
              addICECandidate: function (candidate) {
                  console.log('addICE: got candidate: ', candidate.candidate);
                  peerConnection.addIceCandidate(new IceCandidate({ sdpMLineIndex: candidate.sdpMLineIndex, candidate: candidate.candidate }));
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
          var wsAddr = 'wss://' + window.location.host + window.location.pathname;
          var peerConnection = PeerConnection(makePeerConfig());
          var webSocket = new WebSocket(wsAddr);
          // configure the signalling WebSocket
          webSocket.onmessage = function (event) {
              console.log('received a message: ', event.data);
              onIncomingMessage(JSON.parse(event.data));
          };
          webSocket.push = webSocket.send;
          webSocket.send = function(data) { webSocket.push(JSON.stringify(data)); };
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
                  }, function (e){ console.log(e) });
              }
          };
      };
    </script>
    <script>
      navigator.getUserMedia = navigator.webkitGetUserMedia || navigator.mozGetUserMedia;
      var config = { video: document.getElementById('remote-video') };
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

      function requestFullscreen(){
        var e = document.body;
        if(e.requestFullscreen) e.requestFullscreen();
        else if(e.webkitRequestFullscreen) e.webkitRequestFullscreen();
        else if(e.mozRequestFullScreen) e.mozRequestFullScreen();
        else if(e.msRequestFullscreen) e.msRequestFullscreen();
      }
      document.getElementById('local-video').addEventListener('click', requestFullscreen);
      document.getElementById('local-video').addEventListener('touch', requestFullscreen);

      function toggleLayout(){
        var local = document.getElementById('local-video');
        var remote = document.getElementById('remote-video');
        if(local.classList.contains('small-video')){
          local.classList.remove('small-video');
          remote.classList.remove('big-video');
          local.classList.add('split-video');
          remote.classList.add('split-video');
        }else{
          local.classList.remove('split-video');
          remote.classList.remove('split-video');
          local.classList.add('small-video');
          remote.classList.add('big-video');
        }
      }
      document.getElementById('remote-video').addEventListener('click', toggleLayout);
      document.getElementById('remote-video').addEventListener('touch', toggleLayout);

      if(!(/Chrome/.test(navigator.userAgent) && /Google Inc/.test(navigator.vendor))){
        alert("Seems like you're not using Chrome. Go ahead and try but take this as a fair warning: I never got this to work right in anything else but Chrome.");
      }
    </script>
  </body>
</html>
