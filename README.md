vidup
=====

Tiny Ruby App That Allows Browser Based Video Chatting


installation
------------

I suggest getting a recent Ruby version with [RBENV](https://github.com/sstephenson/rbenv) or [RVM](http://rvm.io/), install [Bundler](http://bundler.io/) and then run:

`bundle install`

usage
-----

~~start with: `ruby vidup.rb`~~

start with: `ruby vidup_ssl.rb`

EDIT: Since Google decided to not allow WebRTC over non-https sites in Chrome anymore, I updated and created a new version: vidup_ssl.rb. Also see nginx-server.conf.example. For free ssl certs check out letsencrypt.

use with Chrome/Chromium (if you can get it to work with Firefox, tell me how. If you can get it to work between Firefox and Chrome, I'll make you a you're-awesome-badge!)


**warning:**
------------

Sometimes it works really great, sometimes it does not. Pull requests welcome!

EDIT: The new https version (vidup_ssl.rb) seems to be a bit more stable.
