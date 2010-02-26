#
#== mpdserver.rb
#
# This is the test server for librmpd. It is a 'shallow' server,
# it implements only the client/server protocol in a highly
# scriptable manner. This means you can set up your own simple
# test music database for testing an mpd client. You can now
# distribute your unit tests (you do have unit tests, yes?) along
# with a test database (a YAML file), and anyone can check that
# your client is in working order.
#
#== Usage
#
# The MPD Server is a subclass of GServer, so you have a lot of
# flexibility at your disposal. The constructor of the server object
# takes the port, an optional YAML database file, and any args for GServer.
#
# The YAML database file can be one of your own creation, or you can use
# one supplied by librmpd (default)
#
# Example:
#
#  require 'rubygems'
#  require 'librmpd'
#  require 'mpdserver'
#
#  server = MPDTestServer.new 7700
#  server.start
#
# You can then enable auditing to see what commands are run by a client:
#
#  server.audit = true
#
# This will print any commands from a client to stdout
#
#=== Unit Testing
#
# For unit testing a client using the test server, I recommend using the
# set up and tear down methods to initialize and destroy a test server.
#
#  def setup
#   @server = MPDTestServer.new 7700
#   @server.start
#  end
#
#  def teardown
#   @server.stop
#  end
#
# This will ensure you are using a clean server instance for each test.

require 'gserver'
require 'yaml'

class MPDTestServer < GServer

  def initialize( port, db_file = nil, *args )
    super port, *args

    if db_file.nil?
      db_file = __FILE__.gsub(/\/[^\/]*$/, '') + '/../data/database.yaml'
    end

    @status = {
      :volume => 0,
      :repeat => 0,
      :random => 0,
      :playlist => 1,
      :state => 'stop',
      :xfade => 0
    }
    @elapsed_time = 0
    @current_song = nil
    @database = YAML::load( File.open( db_file ) )
    @songs = @database[0]
    @playlists = @database[1]
    @artists = []
    @albums = []
    @titles = []
    @the_playlist = []
    @playback_thread = nil
    @filetree = {:name =>'', :dirs =>[], :songs =>[]}
    @songs.each_with_index do |song,i|
      song['id'] = i
      if !song['artist'].nil? and !@artists.include? song['artist']
        @artists << song['artist']
      end
      if !song['album'].nil? and !@albums.include? song['album']
        @albums << song['album']
      end
      if !song['title'].nil?
        @titles << song['title']
      end
      if !song['file'].nil?
        dirs = song['file'].split '/'
        dirs.pop
        the_dir = @filetree
        dirs.each do |d|
          found = nil
          the_dir[:dirs].each do |sub|
            if sub[:name] == d
              found = sub
              break
            end
          end
          if found.nil?
            found = {:name => d, :dirs =>[], :songs =>[]}
            the_dir[:dirs] << found
          end
          the_dir = found
        end # End dirs.each
        the_dir[:songs] << song
      end # End if !song['file'].nil?
    end # End @songs.each

    sort_dir @filetree
    @artists.sort!
    @albums.sort!
    @titles.sort!
  end

  def start
    super

    @playback_thread = Thread.new(@status, self) do |status, server|
      while not server.stopped?
        if status[:state] == 'play'
          song = server.get_current_song
          if song.nil?
            server.elapsed_time = 0
            status[:state] = 'stop'
            next
          end

          status[:time] = "#{server.elapsed_time}:#{song['time']}"
          status[:bitrate] = 192
          status[:audio] = '44100:16:2'

          if server.elapsed_time >= song['time'].to_i
            server.elapsed_time = 0
            server.next_song
          end

          server.elapsed_time = server.elapsed_time + 1
        elsif status[:state] == 'pause'
          song = server.get_current_song
          if song.nil?
            server.elapsed_time = 0
            status[:state] = 'stop'
            next
          end
          status[:time] = "#{server.elapsed_time}:#{song['time']}"
          status[:bitrate] = 192
          status[:audio] = '44100:16:2'
        else
          status[:time] = nil
          status[:bitrate] = nil
          status[:audio] = nil
          server.elapsed_time = 0
        end
        sleep 1
      end
    end
  end
  
  def serve( sock )
    command_list = []
    in_cmd_list = false
    in_ok_list = false
    the_error = nil
    sock.puts 'OK MPD 0.11.5'
    begin
      while line = sock.gets

        args = build_args line

        cmd = args.shift

        if cmd == 'command_list_begin' and args.length == 0 and !in_cmd_list
          in_cmd_list = true
          log 'MPD: Starting Command List' if audit
        elsif cmd == 'command_list_ok_begin' and args.length == 0 and !in_cmd_list
          in_cmd_list = true
          in_ok_list = true
          log 'MPD: Starting Command OK List' if audit
        elsif cmd == 'command_list_end' and in_cmd_list
          log 'MPD: Running Command List' if audit

          the_ret = true
          command_list.each_with_index do |set,i|
            the_ret = do_cmd sock, set[0], set[1]

            if audit
              log "MPD Command List: CMD ##{i}: \"#{set[0]}(#{set[1].join(', ')})\": " + (the_ret ? 'successful' : 'failed')
            end
            
            break unless the_ret

            sock.puts 'list_OK' if in_ok_list
            
          end

          sock.puts 'OK' if the_ret

          command_list.clear
          in_cmd_list = false
          in_ok_list = false
        else
          if in_cmd_list
            command_list << [cmd, args]
          else
            ret = do_cmd sock, cmd, args
            sock.puts 'OK' if ret
            if audit
              log "MPD Command \"#{cmd}(#{args.join(', ')})\": " + (ret ? 'successful' : 'failed')
            end # End if audit
          end # End if in_cmd_list
        end # End if cmd == 'comand_list_begin' ...
      end # End while line = sock.gets
    rescue
    end
  end

  def do_cmd( sock, cmd, args )
    case cmd
    when 'add'
      if args.length == 0
        # Add the entire database
        @songs.each do |s|
          s['_mod_ver'] = @status[:playlist]
          incr_version
          @the_playlist << s
        end
        return true
      else
        # Add a single entry
        the_song = nil
        @songs.each do |s|
          if s['file'] == args[0]
            the_song = s
            break
          end
        end

        if the_song.nil?
          dir = locate_dir(args[0])
          if not dir.nil?
            # Add the dir
            add_dir_to_pls dir
            return true
          else
            return(cmd_fail(sock,'ACK [50@0] {add} directory or file not found'))
          end
        else
          the_song['_mod_ver'] = @status[:playlist]
          incr_version
          @the_playlist << the_song
          return true
        end
      end
    when 'clear'
      args_check( sock, cmd, args, 0 ) do
        incr_version
        @the_playlist = []
        @current_song = nil
        return true
      end
    when 'clearerror'
      args_check( sock, cmd, args, 0 ) do
        the_error = nil
        return true
      end
    when 'close'
      sock.close
      return true
    when 'crossfade'
      args_check( sock, cmd, args, 1 ) do |args|
        if is_int(args[0]) and args[0].to_i >= 0
          @status[:xfade] = args[0].to_i
          return true
        else
          return(cmd_fail(sock,"ACK [2@0] {crossfade} \"#{args[0]}\" is not a integer >= 0"))
        end
      end
    when 'currentsong'
      args_check( sock, cmd, args, 0 ) do
        if @current_song != nil and @current_song < @the_playlist.length
          send_song sock, @the_playlist[@current_song]
        end
        return true
      end
    when 'delete'
      args_check( sock, cmd, args, 1 ) do |args|
        if is_int args[0]
          if args[0].to_i < 0 or args[0].to_i >= @the_playlist.length
            return(cmd_fail(sock,"ACK [50@0] {delete} song doesn't exist: \"#{args[0]}\""))
          else
            @the_playlist.delete_at args[0].to_i
            args[0].to_i.upto @the_playlist.length - 1 do |i|
              @the_playlist[i]['_mod_ver'] = @status[:playlist]
            end
            incr_version
            return true
          end
        else
          return(cmd_fail('ACK [2@0] {delete} need a positive integer'))
        end
      end
    when 'deleteid'
      args_check( sock, cmd, args, 1 ) do |args|
        if is_int args[0]
          the_song = nil
          @the_playlist.each do |song|
            if song['id'] == args[0].to_i
              the_song = song
              break
            end
          end

          if not the_song.nil?
            index = @the_playlist.index the_song
            @the_playlist.delete the_song
            index.upto @the_playlist.length - 1 do |i|
              @the_playlist[i]['_mod_ver'] = @status[:playlist]
            end
            incr_version
            return true
          else
            return(cmd_fail(sock,"ACK [50@0] {deleteid} song id doesn't exist: \"#{args[0]}\""))
          end
        else
          return(cmd_fail(sock,'ACK [2@0] {deleteid} need a positive integer'))
        end
      end
    when 'find'
      args_check( sock, cmd, args, 2 ) do |args|
        if args[0] != 'album' and args[0] != 'artist' and args[0] != 'title'
          return(cmd_fail(sock,'ACK [2@0] {find} incorrect arguments'))
        else
          if args[0] == 'album'
            @songs.each do |song|
              if song['album'] == args[1]
                send_song sock, song
              end
            end
          elsif args[0] == 'artist'
            @songs.each do |song|
              if song['artist'] == args[1]
                send_song sock, song
              end
            end
          elsif args[0] == 'title'
            @songs.each do |song|
              if song['title'] == args[1]
                send_song sock, song
              end
            end
          end
          return true
        end
      end
    when 'kill'
      args_check( sock, cmd, args, 0 ) do
        sock.close
        return true
      end
    when 'list'
      args_check( sock, cmd, args, 1..2 ) do |args|
        if args[0] != 'album' and args[0] != 'artist' and args[0] != 'title'
          return(cmd_fail(sock,"ACK [2@0] {list} \"#{args[0]}\" is not known"))
        elsif args[0] == 'artist' and args.length > 1
          return(cmd_fail(sock,'ACK [2@0] {list} should be "Album" for 3 arguments'))
        else
          if args[0] == 'artist'
            # List all Artists
            @artists.each do |artist|
              sock.puts "Artist: #{artist}"
            end
            return true
          elsif args[0] == 'title'
            # List all Titles
            @titles.each do |title|
              sock.puts "Title: #{title}"
            end
            return true
          else
            if args.length == 2
              # List all Albums by Artist
              # artist == args[1]
              listed = []
              @songs.each do |song|
                if song['artist'] == args[1]
                  if not song['album'].nil? and !listed.include? song['album']
                    sock.puts "Album: #{song['album']}"
                    listed << song['album']
                  end
                end
              end
              return true
            else
              # List all Albums
              @albums.each do |album|
                sock.puts "Album: #{album}"
              end
              return true
            end
          end
        end
      end
    when 'listall'
      args_check( sock, cmd, args, 0..1 ) do |args|
        if args.length == 0
          @filetree[:dirs].each do |d|
            send_dir sock, d, false
          end
        else
          was_song = false
          @songs.each do |song|
            if song['file'] == args[0]
              sock.puts "file: #{song['file']}"
              was_song = true
              break
            end
          end

          if was_song
            return true
          end

          dir = locate_dir args[0]
          if not dir.nil?
            parents = args[0].split '/'
            parents.pop
            parents = parents.join '/'
            parents += '/' unless parents.length == 0
            send_dir sock, dir, false, parents
          else
            return(cmd_fail(sock,'ACK [50@0] {listall} directory or file not found'))
          end
        end
        return true
      end
    when 'listallinfo'
      args_check( sock, cmd, args, 0..1 ) do |args|
        if args.length == 0
          @filetree[:dirs].each do |d|
            send_dir sock, d, true
          end
        else
          was_song = false
          @songs.each do |song|
            if song['file'] == args[0]
              send_song song
              was_song = true
              break
            end
          end

          if was_song
            return true
          end

          dir = locate_dir args[0]
          if not dir.nil?
            parents = args[0].split '/'
            parents.pop
            parents = parents.join '/'
            parents += '/' unless parents.length == 0
            send_dir sock, dir, true, parents
          else
            return(cmd_fail(sock,'ACK [50@0] {listallinfo} directory or file not found'))
          end
        end
        return true
      end
    when 'load'
      args_check( sock, cmd, args, 1 ) do
        # incr_version for each song loaded
        pls = args[0] + '.m3u'
        the_pls = nil
        @playlists.each do |p|
          if p['file'] == pls
            the_pls = p
            break
          end
        end

        unless the_pls.nil?
          the_pls['songs'].each do |song|
            song['_mod_ver'] = @status[:playlist]
            @the_playlist << song
            incr_version
          end
        else
          return(cmd_fail(sock,"ACK [50@0] {load} playlist \"#{args[0]}\" not found"))
        end
      end
    when 'lsinfo'
      args_check( sock, cmd, args, 0..1 ) do
        if args.length == 0
          @filetree[:dirs].each do |d|
            sock.puts "directory: #{d[:name]}"
            d[:songs].each do |s|
              send_song sock, s
            end
          end
          @playlists.each do |pls|
            sock.puts "playlist: #{pls['file'].gsub( /\.m3u$/, '' )}"
          end
        else
          dir = locate_dir args[0]
          if dir.nil?
            return(cmd_fail(sock,"ACK [50@0] {lsinfo} directory not found"))
          else
            dir[:dirs].each do |d|
              sock.puts "directory: #{args[0] + '/' + d[:name]}"
            end
            dir[:songs].each do |s|
              send_song sock, s
            end
          end
        end
        return true
      end
    when 'move'
      args_check( sock, cmd, args, 2 ) do |args|
        if !is_int args[0]
          return(cmd_fail(sock,"ACK [2@0] {move} \"#{args[0]}\" is not a integer"))
        elsif !is_int args[1]
          return(cmd_fail(sock,"ACK [2@0] {move} \"#{args[1]}\" is not a integer"))
        elsif args[0].to_i < 0 or args[0].to_i >= @the_playlist.length
          return(cmd_fail(sock,"ACK [50@0] {move} song doesn't exist: \"#{args[0]}\""))
        elsif args[1].to_i < 0 or args[1].to_i >= @the_playlist.length
          return(cmd_fail(sock,"ACK [50@0] {move} song doesn't exist: \"#{args[1]}\""))
        else
          tmp = @the_playlist.delete_at args[0].to_i
          @the_playlist.insert args[1].to_i, tmp
          if args[0].to_i < args[1].to_i
            args[0].to_i.upto args[1].to_i do |i|
              @the_playlist[i]['_mod_ver'] = @status[:playlist]
            end
          else
            args[1].to_i.upto args[0].to_i do |i|
              @the_playlist[i]['_mod_ver'] = @status[:playlist]
            end
          end
          incr_version
          return true
        end
      end
    when 'moveid'
      args_check( sock, cmd, args, 2 ) do |args|
        if !is_int args[0]
          return(cmd_fail(sock,"ACK [2@0] {moveid} \"#{args[0]}\" is not a integer"))
        elsif !is_int args[1]
          return(cmd_fail(sock,"ACK [2@0] {moveid} \"#{args[1]}\" is not a integer"))
        elsif args[1].to_i < 0 or args[1].to_i >= @the_playlist.length
          return(cmd_fail(sock,"ACK [50@0] {moveid} song doesn't exist: \"#{args[1]}\""))
        else
          # Note: negative args should be checked
          the_song = nil
          index = -1
          @the_playlist.each_with_index do |song,i|
            if song['id'] == args[0].to_i
              the_song = song
              index = i
            end
          end
          if the_song.nil?
            return(cmd_fail(sock,"ACK [50@0] {moveid} song id doesn't exist: \"#{args[0]}\""))
          end
          tmp = @the_playlist.delete_at index
          @the_playlist.insert args[1].to_i, tmp
          if index < args[1].to_i
            index.upto args[1].to_i do |i|
              @the_playlist[i]['_mod_ver'] = @status[:playlist]
            end
          else
            args[1].to_i.upto index do |i|
              @the_playlist[i]['_mod_ver'] = @status[:playlist]
            end
          end
          incr_version
          return true
        end
      end
    when 'next'
      args_check( sock, cmd, args, 0 ) do
        if @status[:state] != 'stop'
          next_song
          @elapsed_time = 0
          @status[:state] = 'play'
        end
        return true
      end
    when 'pause'
      args_check( sock, cmd, args, 0..1 ) do |args|
        if args.length > 0 and not is_bool args[0]
          return(cmd_fail(sock,"ACK [2@0] {pause} \"#{args[0]}\" is not 0 or 1"))
        end
        
        if @status[:state] != 'stop'
          if args.length == 1
            @status[:state] = ( args[0] == '1' ? 'pause' : 'play' )
          else
            @status[:state] = ( @status[:state] == 'pause' ? 'play' : 'pause' )
          end
        end

        return true
      end
    when 'password'
      args_check( sock, cmd, args, 1 ) do |args|
        return true if args[0] == 'test'
        return(cmd_fail(sock,"ACK [3@0] {password} incorrect password"))
      end
    when 'ping'
      args_check( sock, cmd, args, 0 ) do
        return true
      end
    when 'play'
      args_check( sock, cmd, args, 0..1 ) do |args|
        if args.length > 0 and !is_int(args[0])
          return(cmd_fail(sock,'ACK [2@0] {play} need a positive integer'))
        else
          args.clear if args[0] == '-1'
          if args.length == 0
            if @the_playlist.length > 0 and @status[:state] != 'play'
              @current_song = 0 if @current_song.nil?
              @elapsed_time = 0
              @status[:state] = 'play'
            end
          else
            if args[0].to_i < 0 or args[0].to_i >= @the_playlist.length
              return(cmd_fail(sock,"ACK [50@0] {play} song doesn't exist: \"#{args[0]}\""))
            end

            @current_song = args[0].to_i
            @elapsed_time = 0
            @status[:state] = 'play'
          end
          return true
        end
      end
    when 'playid'
      args_check( sock, cmd, args, 0..1 ) do |args|
        if args.length > 0 and !is_int(args[0])
          return(cmd_fail(sock,'ACK [2@0] {playid} need a positive integer'))
        else
          args.clear if args[0] == '-1'
          if args.length == 0
            if @the_playlist.length > 0 and @status[:state] != 'play'
              @current_song = 0 if @current_song.nil?
              @elapsed_time = 0
              @status[:state] = 'play'
            end
          else
            index = nil
            @the_playlist.each_with_index do |s,i|
              if s['id'] == args[0].to_i
                index = i
                break;
              end
            end

            return(cmd_fail(sock,"ACK [50@0] {playid} song id doesn't exist: \"#{args[0]}\"")) if index.nil?

            @current_song = index
            @elapsed_time = 0
            @status[:state] = 'play'
          end
          return true
        end
      end
    when 'playlist'
      log 'MPD Warning: Call to Deprecated API: "playlist"' if audit
      args_check( sock, cmd, args, 0 ) do
        @the_playlist.each_with_index do |v,i|
          sock.puts "#{i}:#{v['file']}"
        end
        return true
      end
    when 'playlistinfo'
      args_check( sock, cmd, args, 0..1 ) do |args|
        if args.length > 0 and !is_int(args[0])
          return(cmd_fail(sock,'ACK [2@0] {playlistinfo} need a positive integer'))
        else
          args.clear if args.length > 0 and args[0].to_i < 0
          if args.length != 0
            if args[0].to_i >= @the_playlist.length
              return(cmd_fail(sock,"ACK [50@0] {playlistinfo} song doesn't exist: \"#{args[0]}\""))
            else
              song = @the_playlist[args[0].to_i]
              send_song sock, song
              sock.puts "Pos: #{args[0].to_i}"
              return true
            end
          else
            @the_playlist.each_with_index do |song,i|
              send_song sock, song
              sock.puts "Pos: #{i}"
            end
            return true
          end
        end
      end
    when 'listplaylistinfo'
      args_check( sock, cmd, args, 1 ) do |args|
        pls = args[0] + '.m3u'
        the_pls = nil
        @playlists.each do |p|
          if p['file'] == pls
            the_pls = p
            break
          end
        end
        unless the_pls.nil?
          the_pls['songs'].each do |song|
            sock.puts "file: #{song['file']}"
          end
        else
          return(cmd_fail(sock,"ACK [50@0] {listplaylistinfo} playlist \"#{args[0]}\" not found"))
        end
        return true
      end
    when 'playlistid'
      args_check( sock, cmd, args, 0..1 ) do |args|
        if args.length > 0 and !is_int(args[0])
          return(cmd_fail(sock,'ACK [2@0] {playlistid} need a positive integer'))
        else
          song = nil
          pos = nil
          args.clear if args[0].to_i < 0
          if args.length != 0
            @the_playlist.each_with_index do |s,i|
              if s['id'] == args[0].to_i
                song = s
                pos = i
                break;
              end
            end

            return(cmd_fail(sock,"ACK [50@0] {playlistid} song id doesn't exist: \"#{args[0]}\"")) if song.nil?

            send_song sock, song
            sock.puts "Pos: #{pos}"
            return true
          else
            @the_playlist.each_with_index do |song,i|
              send_song sock, song
              sock.puts "Pos: #{i}"
            end
            return true
          end
        end
      end
    when 'plchanges'
      args_check( sock, cmd, args, 1 ) do |args|
        if args.length > 0 and !is_int(args[0])
          return(cmd_fail(sock,'ACK [2@0] {plchanges} need a positive integer'))
        else
          # Note: args[0] < 0 just return OK...
          @the_playlist.each_with_index do |song,i|
            if args[0].to_i > @status[:playlist] or song['_mod_ver'] >= args[0].to_i or song['_mod_ver'] == 0
              send_song sock, song
              sock.puts "Pos: #{i}"
            end
          end
          return true
        end
      end
    when 'plchangesposid'
      args_check( sock, cmd, args, 1 ) do |args|
        if args.length > 0 and !is_int(args[0])
          return(cmd_fail(sock,'ACK [2@0] {plchangesposid} need a positive integer'))
        else
          # Note: args[0] < 0 just return OK...
          @the_playlist.each_with_index do |song,i|
            if args[0].to_i > @status[:playlist] or song['_mod_ver'] >= args[0].to_i or song['_mod_ver'] == 0
              sock.puts "cpos: #{i}"
              sock.puts "Id: #{song['id']}"
            end
          end
          return true
        end
      end
    when 'previous'
      args_check( sock, cmd, args, 0 ) do
        return true if @status[:state] == 'stop'
        prev_song
        @elapsed_time = 0
        @status[:state] = 'play'
        return true
      end
    when 'random'
      args_check( sock, cmd, args, 1 ) do |args|
        if is_bool args[0]
          @status[:random] = args[0].to_i
          return true
        elsif is_int args[0]
          return(cmd_fail(sock,"ACK [2@0] {random} \"#{args[0]}\" is not 0 or 1"))
        else
          return(cmd_fail(sock,'ACK [2@0] {random} need an integer'))
        end
      end
    when 'repeat'
      args_check( sock, cmd, args, 1 ) do |args|
        if is_bool args[0]
          @status[:repeat] = args[0].to_i
          return true
        elsif is_int args[0]
          return(cmd_fail(sock,"ACK [2@0] {repeat} \"#{args[0]}\" is not 0 or 1"))
        else
          return(cmd_fail(sock,'ACK [2@0] {repeat} need an integer'))
        end
      end
    when 'rm'
      args_check( sock, cmd, args, 1 ) do |args|
        rm_pls = args[0] + '.m3u'
        the_pls = -1
        @playlists.each_with_index do |pls,i|
          the_pls = i if pls['file'] == rm_pls
        end

        if the_pls != -1
          @playlists.delete_at the_pls
          return true
        else
          return(cmd_fail(sock,"ACK [50@0] {rm} playlist \"#{args[0]}\" not found"))
        end
      end
    when 'save'
      args_check( sock, cmd, args, 1 ) do |args|
        new_playlist = {'file' => args[0]+'.m3u', 'songs' => @the_playlist}
        @playlists << new_playlist
        return true
      end
    when 'search'
      args_check( sock, cmd, args, 2 ) do |args|
        if args[0] != 'title' and args[0] != 'artist' and args[0] != 'album' and args[0] != 'filename'
          return(cmd_fail(sock,'ACK [2@0] {search} incorrect arguments'))
        end
        args[0] = 'file' if args[0] == 'filename'
        @songs.each do |song|
          data = song[args[0]]
          if not data.nil? and data.downcase.include? args[1]
            send_song sock, song
          end
        end
        return true
      end
    when 'seek'
      args_check( sock, cmd, args, 2 ) do |args|
        if !is_int args[0]
          return(cmd_fail(sock,"ACK [2@0] {seek} \"#{args[0]}\" is not a integer"))
        elsif !is_int args[1]
          return(cmd_fail(sock,"ACK [2@0] {seek} \"#{args[1]}\" is not a integer"))
        else
          if args[0].to_i > @the_playlist.length or args[0].to_i < 0
            return(cmd_fail(sock,"ACK [50@0] {seek} song doesn't exist: \"#{args[0]}\""))
          end
          args[1] = '0' if args[1].to_i < 0
          song = @the_playlist[args[0].to_i]
          if args[1].to_i >= song['time'].to_i
            if args[0].to_i + 1 < @the_playlist.length
              @current_song = args[0].to_i + 1
              @elapsed_time = 0
              @status[:state] = 'play' unless @status[:state] == 'pause'
            else
              @current_song = nil
              @elapsed_time = 0
              @status[:state] = 'stop'
            end
          else
            @current_song = args[0].to_i
            @elapsed_time = args[1].to_i
            @status[:state] = 'play' unless @status[:state] == 'pause'
          end
          return true
        end
      end
    when 'seekid'
      args_check( sock, cmd, args, 2 ) do |args|
        if !is_int args[0]
          return(cmd_fail(sock,"ACK [2@0] {seekid} \"#{args[0]}\" is not a integer"))
        elsif !is_int args[1]
          return(cmd_fail(sock,"ACK [2@0] {seekid} \"#{args[1]}\" is not a integer"))
        else
          pos = nil
          song = nil
          @the_playlist.each_with_index do |s,i|
            if s['id'] == args[0].to_i
              song = s
              pos = i
              break;
            end
          end

          if song.nil?
            return(cmd_fail(sock,"ACK [50@0] {seekid} song id doesn't exist: \"#{args[0]}\""))
          end

          args[1] = '0' if args[1].to_i < 0
          if args[1].to_i >= song['time'].to_i
            if pos + 1 < @the_playlist.length
              @current_song = pos + 1
              @elapsed_time = 0
              @status[:state] = 'play' unless @status[:state] == 'pause'
            else
              @current_song = nil
              @elapsed_time = 0
              @status[:state] = 'stop'
            end
          else
            @current_song = pos
            @elapsed_time = args[1].to_i
            @status[:state] = 'play' unless @status[:state] == 'pause'
          end
          return true
        end
      end
    when 'setvol'
      args_check( sock, cmd, args, 1 ) do |args|
        if !is_int args[0]
          return(cmd_fail(sock,'ACK [2@0] {setvol} need an integer'))
        else
          # Note: args[0] < 0 actually sets the vol val to < 0
          @status[:volume] = args[0].to_i
          return true
        end
      end
    when 'shuffle'
      args_check( sock, cmd, args, 0 ) do
        @the_playlist.each do |s|
          s['_mod_ver'] = @status[:playlist]
        end
        incr_version
        @the_playlist.reverse!
        return true
      end
    when 'stats'
      args_check( sock, cmd, args, 0 ) do
        # artists
        sock.puts "artists: #{@artists.size}"
        # albums
        sock.puts "albums: #{@albums.size}"
        # songs
        sock.puts "songs: #{@songs.size}"
        # uptime
        sock.puts "uptime: 500"
        # db_playtime
        time = 0
        @songs.each do |s|
          time += s['time'].to_i
        end
        sock.puts "db_playtime: #{time}"
        # db_update
        sock.puts "db_update: 1159418502"
        # playtime
        sock.puts "playtime: 10"
        return true
      end
    when 'status'
      args_check( sock, cmd, args, 0 ) do
        @status.each_pair do |key,val|
          sock.puts "#{key}: #{val}" unless val.nil?
        end
        sock.puts "playlistlength: #{@the_playlist.length}"

        if @current_song != nil and @the_playlist.length > @current_song
          sock.puts "song: #{@current_song}"
          sock.puts "songid: #{@the_playlist[@current_song]['id']}"
        end

        @status[:updating_db] = nil
        return true
      end
    when 'stop'
      args_check( sock, cmd, args, 0 ) do
        @status[:state] = 'stop'
        @status[:time] = nil
        @status[:bitrate] = nil
        @status[:audio] = nil
        return true
      end
    when 'swap'
      args_check( sock, cmd, args, 2 ) do |args|
        if !is_int args[0]
          return(cmd_fail(sock,"ACK [2@0] {swap} \"#{args[0]}\" is not a integer"))
        elsif !is_int args[1]
          return(cmd_fail(sock,"ACK [2@0] {swap} \"#{args[1]}\" is not a integer"))
        elsif args[0].to_i >= @the_playlist.length or args[0].to_i < 0
          return(cmd_fail(sock,"ACK [50@0] {swap} song doesn't exist: \"#{args[0]}\""))
        elsif args[1].to_i >= @the_playlist.length or args[1].to_i < 0
          return(cmd_fail(sock,"ACK [50@0] {swap} song doesn't exist: \"#{args[1]}\""))
        else
          tmp = @the_playlist[args[1].to_i]
          @the_playlist[args[1].to_i] = @the_playlist[args[0].to_i]
          @the_playlist[args[0].to_i] = tmp
          @the_playlist[args[0].to_i]['_mod_ver'] = @status[:playlist]
          @the_playlist[args[1].to_i]['_mod_ver'] = @status[:playlist]
          incr_version
          return true
        end
      end
    when 'swapid'
      args_check( sock, cmd, args, 2 ) do |args|
        if !is_int args[0]
          return(cmd_fail(sock,"ACK [2@0] {swapid} \"#{args[0]}\" is not a integer"))
        elsif !is_int args[1]
          return(cmd_fail(sock,"ACK [2@0] {swapid} \"#{args[1]}\" is not a integer"))
        else
          from = nil
          to = nil
          @the_playlist.each_with_index do |song,i|
            if song['id'] == args[0].to_i
              from = i
            elsif song['id'] == args[1].to_i
              to = i
            end
          end
          if from.nil?
            return(cmd_fail(sock,"ACK [50@0] {swapid} song id doesn't exist: \"#{args[0]}\""))
          elsif to.nil?
            return(cmd_fail(sock,"ACK [50@0] {swapid} song id doesn't exist: \"#{args[1]}\""))
          end
          tmp = @the_playlist[to]
          @the_playlist[to] = @the_playlist[from]
          @the_playlist[from] = tmp
          @the_playlist[to]['_mod_ver'] = @status[:playlist]
          @the_playlist[from]['_mod_ver'] = @status[:playlist]

          incr_version
          return true
        end
      end
    when 'update'
      args_check( sock, cmd, args, 0..1 ) do |args|
        incr_version
        sock.puts 'updating_db: 1'
        @status[:updating_db] = '1'
        return true
      end
    when 'volume'
      log 'MPD Warning: Call to Deprecated API: "volume"' if audit
      args_check( sock, cmd, args, 1 ) do |args|
        if !is_int args[0]
          return(cmd_fail(sock,'ACK [2@0] {volume} need an integer'))
        else
          # Note: args[0] < 0 subtract from the volume
          @status[:volume] += args[0].to_i
          return true
        end
      end
    else
      return(cmd_fail(sock,"ACK [5@0] {} unknown command #{cmd}"))
    end # End Case cmd
  end

  def get_current_song
    if @current_song != nil and @current_song < @the_playlist.length
      return @the_playlist[@current_song]
    else
      return nil
    end
  end

  def prev_song
    return if @current_song.nil?
    if @current_song == 0
      @elapsed_time = 0
    else
      @current_song -= 1
    end
  end

  def next_song
    return if @current_song.nil?
    @current_song = (@current_song +1 < @the_playlist.length ? @current_song +1 : nil)
  end

  def elapsed_time=( new_time )
    @elapsed_time = new_time
  end

  def elapsed_time
    @elapsed_time
  end

  def incr_version
    if @status[:playlist] == 2147483647
      @status[:playlist] = 1
      @the_playlist.each do |song|
        song['_mod_ver'] = 0
      end
    else
      @status[:playlist] += 1
    end
  end

  def cmd_fail( sock, msg )
    sock.puts msg
    return false
  end

  def build_args( line )
    ret = []
    word = ''
    escaped = false
    in_quote = false

    line.strip!

    line.each_byte do |c|
      c = c.chr
      if c == ' ' and !in_quote
        ret << word unless word.empty?
        word = ''
      elsif c == '"' and !escaped
        if in_quote
          in_quote = false
        else
          in_quote = true
        end
        ret << word unless word.empty?
        word = ''
      else
        escaped = (c == '\\')
        word += c
      end
    end

    ret << word unless word.empty?

    return ret
  end

  def args_check( sock, cmd, argv, argc )
    if (argc.kind_of? Range and argc.include?(argv.length)) or
        (argv.length == argc)
      yield argv
    else
      sock.puts "ACK [2@0] {#{cmd}} wrong number of arguments for \"#{cmd}\""
    end
  end

  def is_int( val )
    val =~ /^[-+]?[0-9]*$/
  end

  def is_bool( val )
    val == '0' or val == '1'
  end

  def locate_dir( path )
    dirs = path.split '/'

    the_dir = @filetree
    dirs.each do |d|
      found = nil
      the_dir[:dirs].each do |sub|
        if sub[:name] == d
          found = sub
          break
        end
      end
      if found.nil?
        return nil
      else
        the_dir = found
      end
    end

    return the_dir
  end

  def send_song( sock, song )
    return if song.nil?
    sock.puts "file: #{song['file']}"
    song.each_pair do |key,val|
      sock.puts "#{key.capitalize}: #{val}" unless key == 'file' or key == '_mod_ver'
    end
  end

  def send_dir( sock, dir, allinfo, path = '' )
    sock.puts "directory: #{path}#{dir[:name]}"

    dir[:songs].each do |song|
      if allinfo
        send_song sock, song
      else
        sock.puts "file: #{song['file']}"
      end
    end

    dir[:dirs].each do |d|
      send_dir(sock, d, allinfo, dir[:name] + '/')
    end
  end

  def add_dir_to_pls( dir )
    dir[:songs].each do |song|
      song['_mod_ver'] = @status[:playlist]
      incr_version
      @the_playlist << song
    end

    dir[:dirs].each do |d|
      add_dir_to_pls d
    end
  end

  def sort_dir( dir )
    dir[:dirs].sort! do |x,y|
      x[:name] <=> y[:name]
    end

    dir[:dirs].each do |d|
      sort_dir d
    end
  end

end
