#
# Unit tests for librmpd test server
#
# This tests the MPDTestServer class

require '../lib/librmpd'
require '../lib/mpdserver'
require 'test/unit'
require 'socket'

class MPDServerTester < Test::Unit::TestCase

  def setup
    begin
      @port = 9393
      @mpd = MPDTestServer.new @port
      @mpd.start
      @sock = TCPSocket.new 'localhost', @port
    rescue Errno::EADDRINUSE
      @port = 9494
      @mpd = MPDTestServer.new @port
      @mpd.start
      @sock = TCPSocket.new 'localhost', @port
    end
  end

  def teardown
    @mpd.stop
  end

  def get_response
    msg = ''
    reading = true
    error = nil
    while reading
      line = @sock.gets
      case line
      when "OK\n"
        reading = false;
      when /^ACK/
        error = line
        reading = false;
      else
        msg += line
      end
    end

    if error.nil?
      return msg
    else
      raise error.gsub( /^ACK \[(\d+)\@(\d+)\] \{(.+)\} (.+)$/, 'MPD Error #\1: \3: \4')
    end
  end

  def build_hash( reply )
    lines = reply.split "\n"

    hash = {}
    lines.each do |l|
      key = l.gsub(/^([^:]*): .*/, '\1')
      hash[key.downcase] = l.gsub( key + ': ', '' )
    end

    return hash
  end

  def build_songs( reply )
    lines = reply.split "\n"

    song = nil
    songs = []
    lines.each do |l|
      if l =~ /^file: /
        songs << song unless song == nil
        song = {}
        song['file'] = l.gsub(/^file: /, '')
      else
        key = l.gsub( /^([^:]*): .*/, '\1' )
        song[key] = l.gsub( key + ': ', '' )
      end
    end

    songs << song

    return songs
  end

  def extract_song( lines )
    song = {}
    lines.each do |l|
      key = l.gsub /^([^:]*): .*/, '\1'
      song[key] = l.gsub key + ': ', ''
    end

    return song
  end

  def test_connect
    assert_equal "OK MPD 0.11.5\n", @sock.gets
  end

  def test_add
    @sock.gets

    # Add w/o args (Adds All Songs)
    @sock.puts 'add'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 46, songs.length

    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    # Add a dir
    @sock.puts 'add Shpongle'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 27, songs.length

    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'add Shpongle/Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 7, songs.length

    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    # Add a song
    @sock.puts 'add Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 1, songs.length
    assert_equal '0:Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', songs[0]

    # Add a non existant item
    @sock.puts 'add ABOMINATION'
    assert_equal "ACK [50@0] {add} directory or file not found\n", @sock.gets
  end

  def test_clear
    @sock.gets

    @sock.puts 'add'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 46, songs.length

    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    assert_equal "OK\n", @sock.gets

    # Test improper args
    @sock.puts 'clear blah'
    assert_equal "ACK [2@0] {clear} wrong number of arguments for \"clear\"\n", @sock.gets
  end

  def test_clearerror
    @sock.gets

    @sock.puts 'clearerror 1'
    assert_equal "ACK [2@0] {clearerror} wrong number of arguments for \"clearerror\"\n", @sock.gets

    @sock.puts 'clearerror'
    assert_equal "OK\n", @sock.gets
  end

  def test_close
    @sock.gets

    # Test improper args
    @sock.puts 'close blah'
    assert_raises(Errno::EPIPE) { @sock.puts 'data' }

    @sock = TCPSocket.new 'localhost', @port
    @sock.puts 'close'
    assert_raises(Errno::EPIPE) { @sock.puts 'data' }

  end

  def test_crossfade
    @sock.gets

    # Test no args
    @sock.puts 'crossfade'
    assert_equal "ACK [2@0] {crossfade} wrong number of arguments for \"crossfade\"\n", @sock.gets

    # Test not a number arg
    @sock.puts 'crossfade a'
    assert_equal "ACK [2@0] {crossfade} \"a\" is not a integer >= 0\n", @sock.gets

    # Test arg < 0
    @sock.puts 'crossfade -1'
    assert_equal "ACK [2@0] {crossfade} \"-1\" is not a integer >= 0\n", @sock.gets

    # Test correct arg
    @sock.puts 'crossfade 10'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    hash = build_hash(get_response)
    assert_equal '10', hash['xfade']

    @sock.puts 'crossfade 49'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    hash = build_hash(get_response)
    assert_equal '49', hash['xfade']
  end

  def test_currentsong
    @sock.gets

    # Test args > 0
    @sock.puts 'currentsong 1'
    assert_equal "ACK [2@0] {currentsong} wrong number of arguments for \"currentsong\"\n", @sock.gets

    @sock.puts 'currentsong'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'currentsong'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'play'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'currentsong'
    songs = build_songs get_response
    assert_equal 1, songs.size
    assert_equal '7', songs[0]['Id']
    assert_equal 'Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', songs[0]['file']

    @sock.puts 'pause'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'currentsong'
    songs = build_songs get_response
    assert_equal 1, songs.size
    assert_equal '7', songs[0]['Id']
    assert_equal 'Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', songs[0]['file']

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'currentsong'
    songs = build_songs get_response
    assert_equal 1, songs.size
    assert_equal '7', songs[0]['Id']
    assert_equal 'Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', songs[0]['file']

    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'currentsong'
    assert_equal "OK\n", @sock.gets
  end

  def test_delete
    @sock.gets

    @sock.puts 'add Shpongle/Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 7, songs.length
    assert_equal '0:Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', songs[0]
    assert_equal '1:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', songs[1]

    # Test correct arg
    @sock.puts 'delete 0'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 6, songs.length
    assert_equal '0:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', songs[0]
    assert_equal '3:Shpongle/Are_You_Shpongled/5.Behind_Closed_Eyelids.ogg', songs[3]
    assert_equal '4:Shpongle/Are_You_Shpongled/6.Divine_Moments_of_Truth.ogg', songs[4]

    @sock.puts 'delete 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 5, songs.length
    assert_equal '0:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', songs[0]
    assert_equal '2:Shpongle/Are_You_Shpongled/4.Shpongle_Spores.ogg', songs[2]
    assert_equal '3:Shpongle/Are_You_Shpongled/6.Divine_Moments_of_Truth.ogg', songs[3]
    assert_equal '4:Shpongle/Are_You_Shpongled/7...._and_the_Day_Turned_to_Night.ogg', songs[4]

    # Test arg == length
    @sock.puts 'delete 5'
    assert_equal "ACK [50@0] {delete} song doesn't exist: \"5\"\n", @sock.gets

    # Test arg > length
    @sock.puts 'delete 900'
    assert_equal "ACK [50@0] {delete} song doesn't exist: \"900\"\n", @sock.gets

    # Test arg < 0
    @sock.puts 'delete -1'
    assert_equal "ACK [50@0] {delete} song doesn't exist: \"-1\"\n", @sock.gets

    # Test no args
    @sock.puts 'delete'
    assert_equal "ACK [2@0] {delete} wrong number of arguments for \"delete\"\n", @sock.gets
  end

  def test_deleteid
    @sock.gets

    @sock.puts 'add Shpongle/Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 7, songs.length
    assert_equal '0:Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', songs[0]
    assert_equal '1:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', songs[1]

    # Test correct arg
    @sock.puts 'deleteid 0'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 6, songs.length
    assert_equal '0:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', songs[0]
    assert_equal '1:Shpongle/Are_You_Shpongled/3.Vapour_Rumours.ogg', songs[1]
    assert_equal '2:Shpongle/Are_You_Shpongled/4.Shpongle_Spores.ogg', songs[2]

    @sock.puts 'deleteid 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 5, songs.length
    assert_equal '0:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', songs[0]
    assert_equal '1:Shpongle/Are_You_Shpongled/3.Vapour_Rumours.ogg', songs[1]
    assert_equal '2:Shpongle/Are_You_Shpongled/5.Behind_Closed_Eyelids.ogg', songs[2]

    # Test arg no present but valid
    @sock.puts 'deleteid 8'
    assert_equal "ACK [50@0] {deleteid} song id doesn't exist: \"8\"\n", @sock.gets

    # Test arg > length
    @sock.puts 'deleteid 900'
    assert_equal "ACK [50@0] {deleteid} song id doesn't exist: \"900\"\n", @sock.gets

    # Test arg < 0
    @sock.puts 'deleteid -1'
    assert_equal "ACK [50@0] {deleteid} song id doesn't exist: \"-1\"\n", @sock.gets

    # Test no args
    @sock.puts 'deleteid'
    assert_equal "ACK [2@0] {deleteid} wrong number of arguments for \"deleteid\"\n", @sock.gets
  end

  def test_find
    @sock.gets

    # Test no args
    @sock.puts 'find'
    assert_equal "ACK [2@0] {find} wrong number of arguments for \"find\"\n", @sock.gets

    # Test one arg
    @sock.puts 'find album'
    assert_equal "ACK [2@0] {find} wrong number of arguments for \"find\"\n", @sock.gets

    # Test incorrect args
    @sock.puts 'find wrong test'
    assert_equal "ACK [2@0] {find} incorrect arguments\n", @sock.gets

    # Test album search
    @sock.puts 'find album "Are You Shpongled?"'
    songs = build_songs(get_response)
    assert_equal 7, songs.length
    assert_equal 'Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', songs[0]['file']
    assert_equal 'Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', songs[1]['file']
    assert_equal 'Shpongle/Are_You_Shpongled/3.Vapour_Rumours.ogg', songs[2]['file']
    assert_equal 'Shpongle/Are_You_Shpongled/4.Shpongle_Spores.ogg', songs[3]['file']
    assert_equal 'Shpongle/Are_You_Shpongled/5.Behind_Closed_Eyelids.ogg', songs[4]['file']
    assert_equal 'Shpongle/Are_You_Shpongled/6.Divine_Moments_of_Truth.ogg', songs[5]['file']
    assert_equal 'Shpongle/Are_You_Shpongled/7...._and_the_Day_Turned_to_Night.ogg', songs[6]['file']

    songs.each_with_index do |s,i|
      assert_equal 'Shpongle', s['Artist']
      assert_equal 'Are You Shpongled?', s['Album']
      assert_equal (i+1).to_s, s['Track']
      assert_not_nil s['Time']
    end

    # Test artist search
    @sock.puts 'find artist "Carbon Based Lifeforms"'
    songs = build_songs(get_response)
    assert_equal 11, songs.length
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/01.Central_Plains.ogg', songs[0]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/02.Tensor.ogg', songs[1]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/03.MOS_6581_(Album_Version).ogg', songs[2]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/04.Silent_Running.ogg', songs[3]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/05.Neurotransmitter.ogg', songs[4]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/06.Hydroponic_Garden.ogg', songs[5]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/07.Exosphere.ogg', songs[6]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/08.Comsat.ogg', songs[7]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/09.Epicentre_(First_Movement).ogg', songs[8]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/10.Artificial_Island.ogg', songs[9]['file']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/11.Refraction_1.33.ogg', songs[10]['file']

    songs.each_with_index do |s,i|
      assert_equal 'Carbon Based Lifeforms', s['Artist']
      assert_equal 'Hydroponic Garden', s['Album']
      assert_equal (i+1).to_s, s['Track']
      assert_not_nil s['Time']
    end

    # Test title search
    @sock.puts 'find title "Ambient Galaxy (Disco Valley Mix)"'
    songs = build_songs(get_response)
    assert_equal 1, songs.length
    assert_equal 'Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', songs[0]['file']
    assert_equal 'Astral Projection', songs[0]['Artist']
    assert_equal 'Dancing Galaxy', songs[0]['Album']
    assert_equal 'Ambient Galaxy (Disco Valley Mix)', songs[0]['Title']
    assert_equal '8', songs[0]['Track']
    assert_equal '825', songs[0]['Time']

  end

  def test_kill
    @sock.gets

    @sock.puts 'kill'
    assert_raises(Errno::EPIPE) { @sock.puts 'data' }
  end

  def test_list
    @sock.gets

    # Test no args
    @sock.puts 'list'
    assert_equal "ACK [2@0] {list} wrong number of arguments for \"list\"\n", @sock.gets

    # Test wrong args
    @sock.puts 'list bad'
    assert_equal "ACK [2@0] {list} \"bad\" is not known\n", @sock.gets

    # Test wrong args
    @sock.puts 'list bad blah'
    assert_equal "ACK [2@0] {list} \"bad\" is not known\n", @sock.gets

    # Test wrong args
    @sock.puts 'list artist blah'
    assert_equal "ACK [2@0] {list} should be \"Album\" for 3 arguments\n", @sock.gets

    # Test album
    @sock.puts 'list album'
    reply = get_response
    albums = reply.split "\n"
    assert_equal 4, albums.length
    assert_equal 'Album: Are You Shpongled?', albums[0]
    assert_equal 'Album: Dancing Galaxy', albums[1]
    assert_equal 'Album: Hydroponic Garden', albums[2]
    assert_equal 'Album: Nothing Lasts... But Nothing Is Lost', albums[3]

    # Test album + artist
    @sock.puts 'list album Shpongle'
    reply = get_response
    albums = reply.split "\n"
    assert_equal 2, albums.length
    assert_equal 'Album: Are You Shpongled?', albums[0]
    assert_equal 'Album: Nothing Lasts... But Nothing Is Lost', albums[1]

    # Test album + non artist
    @sock.puts 'list album zero'
    assert_equal "OK\n", @sock.gets

    # Test artist
    @sock.puts 'list artist'
    reply = get_response
    artists = reply.split "\n"
    assert_equal 3, artists.length
    assert_equal 'Artist: Astral Projection', artists[0]
    assert_equal 'Artist: Carbon Based Lifeforms', artists[1]
    assert_equal 'Artist: Shpongle', artists[2]

    # Test title
    @sock.puts 'list title'
    reply = get_response
    titles = reply.split "\n"
    assert_equal 46, titles.length
    assert_equal 'Title: ... and the Day Turned to Night', titles[0]
    assert_equal 'Title: ...But Nothing Is Lost', titles[1]
    assert_equal 'Title: When Shall I Be Free', titles[45]

  end

  def test_listall
    @sock.gets

    # Test too many args
    @sock.puts 'listall blah blah'
    assert_equal "ACK [2@0] {listall} wrong number of arguments for \"listall\"\n", @sock.gets

    # Test no args
    @sock.puts 'listall'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 53, lines.length
    assert_equal 'directory: Astral_Projection', lines[0]
    assert_equal 'directory: Astral_Projection/Dancing_Galaxy', lines[1]
    assert_equal 'file: Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[2]
    for i in 3...10
      assert lines[i] =~ /^file: Astral_Projection\/Dancing_Galaxy\//
    end

    assert_equal 'directory: Carbon_Based_Lifeforms', lines[10]
    assert_equal 'directory: Carbon_Based_Lifeforms/Hydroponic_Garden', lines[11]
    assert_equal 'file: Carbon_Based_Lifeforms/Hydroponic_Garden/01.Central_Plains.ogg', lines[12]
    for i in 13...23
      assert lines[i] =~ /^file: Carbon_Based_Lifeforms\/Hydroponic_Garden\//
    end

    assert_equal 'directory: Shpongle', lines[23]
    assert_equal 'directory: Shpongle/Are_You_Shpongled', lines[24]
    assert_equal 'file: Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', lines[25]
    for i in 26...32
      assert lines[i] =~ /^file: Shpongle\/Are_You_Shpongled\//
    end

    assert_equal 'directory: Shpongle/Nothing_Lasts..._But_Nothing_Is_Lost', lines[32]
    assert_equal 'file: Shpongle/Nothing_Lasts..._But_Nothing_Is_Lost/01.Botanical_Dimensions.ogg', lines[33]
    for i in 34...53
      assert lines[i] =~ /^file: Shpongle\/Nothing_Lasts..._But_Nothing_Is_Lost\//
    end

    # Test one arg
    @sock.puts 'listall Carbon_Based_Lifeforms'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 13, lines.length
    assert_equal 'directory: Carbon_Based_Lifeforms', lines[0]
    assert_equal 'directory: Carbon_Based_Lifeforms/Hydroponic_Garden', lines[1]
    assert_equal 'file: Carbon_Based_Lifeforms/Hydroponic_Garden/01.Central_Plains.ogg', lines[2]
    for i in 2...13
      assert lines[i] =~ /^file: Carbon_Based_Lifeforms\/Hydroponic_Garden\//
    end

    @sock.puts 'listall Shpongle/Are_You_Shpongled'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.length
    assert_equal 'directory: Shpongle/Are_You_Shpongled', lines[0]
    assert_equal 'file: Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', lines[1]
    for i in 2...8
      assert lines[i] =~ /^file: Shpongle\/Are_You_Shpongled\//
    end

    @sock.puts 'listall nothere'
    assert_equal "ACK [50@0] {listall} directory or file not found\n", @sock.gets

    @sock.puts 'listall Shpongle/nothere'
    assert_equal "ACK [50@0] {listall} directory or file not found\n", @sock.gets

  end

  def test_listallinfo
    @sock.gets

    # Test too many args
    @sock.puts 'listallinfo blah blah'
    assert_equal "ACK [2@0] {listallinfo} wrong number of arguments for \"listallinfo\"\n", @sock.gets

    # Test no args
    @sock.puts 'listallinfo'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 329, lines.length
    assert_equal 'directory: Astral_Projection', lines[0]
    assert_equal 'directory: Astral_Projection/Dancing_Galaxy', lines[1]
    assert_equal 'file: Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[2]
    song = extract_song lines[3..8]
    assert_equal 'Astral Projection', song['Artist']
    assert_equal 'Dancing Galaxy', song['Album']
    assert_equal 'Dancing Galaxy', song['Title']
    assert_equal '558', song['Time']
    assert_equal '1', song['Track']
    assert_equal '7', song['Id']

    song_num = 1
    while song_num < 8
      index = (song_num * 7) + 2
      song = extract_song lines[index..(index+6)]
      assert_equal 'Astral Projection', song['Artist']
      assert_equal 'Dancing Galaxy', song['Album']
      assert_equal (song_num+1).to_s, song['Track']
      assert_equal (song_num+7).to_s, song['Id']
      assert_not_nil song['Time']
      assert_not_nil song['Title']
      assert_not_nil song['file']
      song_num += 1
    end

    assert_equal 'directory: Carbon_Based_Lifeforms', lines[58]
    assert_equal 'directory: Carbon_Based_Lifeforms/Hydroponic_Garden', lines[59]
    assert_equal 'file: Carbon_Based_Lifeforms/Hydroponic_Garden/01.Central_Plains.ogg', lines[60]

    song = extract_song lines[61..66]
    assert_equal 'Carbon Based Lifeforms', song['Artist']
    assert_equal 'Hydroponic Garden', song['Album']
    assert_equal 'Central Plains', song['Title']
    assert_equal '1', song['Track']
    assert_equal '15', song['Id']

    song_num = 1
    while song_num < 11
      index = (song_num * 7) + 60
      song = extract_song lines[index..(index+6)]
      assert_equal 'Carbon Based Lifeforms', song['Artist']
      assert_equal 'Hydroponic Garden', song['Album']
      assert_equal (song_num+1).to_s, song['Track']
      assert_equal (song_num+15).to_s, song['Id']
      assert_not_nil song['Time']
      assert_not_nil song['Title']
      assert_not_nil song['file']
      song_num += 1
    end

    assert_equal 'directory: Shpongle', lines[137]
    assert_equal 'directory: Shpongle/Are_You_Shpongled', lines[138]
    assert_equal 'file: Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', lines[139]

    song = extract_song lines[140..145]
    assert_equal 'Shpongle', song['Artist']
    assert_equal 'Are You Shpongled?', song['Album']
    assert_equal 'Shpongle Falls', song['Title']
    assert_equal '1', song['Track']
    assert_equal '0', song['Id']

    song_num = 1
    while song_num < 7
      index = (song_num * 7) + 139
      song = extract_song lines[index..(index+6)]
      assert_equal 'Shpongle', song['Artist']
      assert_equal 'Are You Shpongled?', song['Album']
      assert_equal (song_num+1).to_s, song['Track']
      assert_equal (song_num).to_s, song['Id']
      assert_not_nil song['Time']
      assert_not_nil song['Title']
      assert_not_nil song['file']
      song_num += 1
    end

    assert_equal 'directory: Shpongle/Nothing_Lasts..._But_Nothing_Is_Lost', lines[188]
    assert_equal 'file: Shpongle/Nothing_Lasts..._But_Nothing_Is_Lost/01.Botanical_Dimensions.ogg', lines[189]

    song = extract_song lines[190..195]
    assert_equal 'Shpongle', song['Artist']
    assert_equal 'Nothing Lasts... But Nothing Is Lost', song['Album']
    assert_equal 'Botanical Dimensions', song['Title']
    assert_equal '1', song['Track']
    assert_equal '26', song['Id']

    song_num = 1
    while song_num < 20
      index = (song_num * 7) + 189
      song = extract_song lines[index..(index+6)]
      assert_equal 'Shpongle', song['Artist']
      assert_equal 'Nothing Lasts... But Nothing Is Lost', song['Album']
      assert_equal (song_num+1).to_s, song['Track']
      assert_equal (song_num+26).to_s, song['Id']
      assert_not_nil song['Time']
      assert_not_nil song['Title']
      assert_not_nil song['file']
      song_num += 1
    end

    # Test one arg that doesn't exist
    @sock.puts 'listallinfo noentry'
    assert_equal "ACK [50@0] {listallinfo} directory or file not found\n", @sock.gets

    # Test one arg that exists
    @sock.puts 'listallinfo Carbon_Based_Lifeforms'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 'directory: Carbon_Based_Lifeforms', lines[0]
    assert_equal 'directory: Carbon_Based_Lifeforms/Hydroponic_Garden', lines[1]
    lines.shift
    lines.shift
    reply = lines.join "\n"
    songs = build_songs reply
    
    songs.each_with_index do |s,i|
      assert_equal 'Carbon Based Lifeforms', s['Artist']
      assert_equal 'Hydroponic Garden', s['Album']
      assert_equal (i+1).to_s, s['Track']
      assert_equal (i+15).to_s, s['Id']
      assert_not_nil s['Time']
      assert_nil s['directory']
    end
  end

  def test_load
    @sock.gets

    # Test no args
    @sock.puts 'load'
    assert_equal "ACK [2@0] {load} wrong number of arguments for \"load\"\n", @sock.gets

    # Test args > 1
    @sock.puts 'load blah blah'
    assert_equal "ACK [2@0] {load} wrong number of arguments for \"load\"\n", @sock.gets

    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    # Test arg doesn't exist
    @sock.puts 'load nopls'
    assert_equal "ACK [50@0] {load} playlist \"nopls\" not found\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '0', status['playlistlength']

    # Test arg that exists but contains m3u
    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy.m3u'
    assert_equal "ACK [50@0] {load} playlist \"Astral_Projection_-_Dancing_Galaxy.m3u\" not found\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '0', status['playlistlength']

    # Test correct arg
    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '8', status['playlistlength']

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.length
    assert_equal '0:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[0]
    assert_equal '1:Astral_Projection/Dancing_Galaxy/2.Soundform.ogg', lines[1]
    assert_equal '2:Astral_Projection/Dancing_Galaxy/3.Flying_Into_A_Star.ogg', lines[2]
    assert_equal '3:Astral_Projection/Dancing_Galaxy/4.No_One_Ever_Dreams.ogg', lines[3]
    assert_equal '4:Astral_Projection/Dancing_Galaxy/5.Cosmic_Ascension_(ft._DJ_Jorg).ogg', lines[4]
    assert_equal '5:Astral_Projection/Dancing_Galaxy/6.Life_On_Mars.ogg', lines[5]
    assert_equal '6:Astral_Projection/Dancing_Galaxy/7.Liquid_Sun.ogg', lines[6]
    assert_equal '7:Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', lines[7]
  end

  def test_lsinfo
    @sock.gets

    # Test args > 1
    @sock.puts 'lsinfo 1 2'
    assert_equal "ACK [2@0] {lsinfo} wrong number of arguments for \"lsinfo\"\n", @sock.gets

    # Test arg not exist
    @sock.puts 'lsinfo abomination'
    assert_equal "ACK [50@0] {lsinfo} directory not found\n", @sock.gets

    @sock.puts 'lsinfo Shpongle/a'
    assert_equal "ACK [50@0] {lsinfo} directory not found\n", @sock.gets

    # Test no args
    @sock.puts 'lsinfo'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 5, lines.length
    assert_equal 'directory: Astral_Projection', lines[0]
    assert_equal 'directory: Carbon_Based_Lifeforms', lines[1]
    assert_equal 'directory: Shpongle', lines[2]
    assert_equal 'playlist: Shpongle_-_Are_You_Shpongled', lines[3]
    assert_equal 'playlist: Astral_Projection_-_Dancing_Galaxy', lines[4]

    # Test arg
    @sock.puts 'lsinfo Shpongle'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 2, lines.length
    assert_equal 'directory: Shpongle/Are_You_Shpongled', lines[0]
    assert_equal 'directory: Shpongle/Nothing_Lasts..._But_Nothing_Is_Lost', lines[1]

    @sock.puts 'lsinfo Astral_Projection/Dancing_Galaxy'
    songs = build_songs get_response
    assert_equal 8, songs.length
    songs.each_with_index do |s,i|
      assert s['file'] =~ /^Astral_Projection\/Dancing_Galaxy\//
      assert_equal 'Astral Projection', s['Artist']
      assert_equal 'Dancing Galaxy', s['Album']
      assert_not_nil s['Title']
      assert_not_nil s['Time']
      assert_equal (i+1).to_s, s['Track']
      assert_equal (i+7).to_s, s['Id']
    end
  end

  def test_move
    @sock.gets

    # Test args == 0
    @sock.puts 'move'
    assert_equal "ACK [2@0] {move} wrong number of arguments for \"move\"\n", @sock.gets

    # Test args > 2
    @sock.puts 'move 1 2 3'
    assert_equal "ACK [2@0] {move} wrong number of arguments for \"move\"\n", @sock.gets

    # Test args not integers
    @sock.puts 'move a b'
    assert_equal "ACK [2@0] {move} \"a\" is not a integer\n", @sock.gets

    @sock.puts 'move 1 b'
    assert_equal "ACK [2@0] {move} \"b\" is not a integer\n", @sock.gets

    # Test arg doesn't exist
    @sock.puts 'move 1 2'
    assert_equal "ACK [50@0] {move} song doesn't exist: \"1\"\n", @sock.gets

    @sock.puts 'load Shpongle_-_Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'move 1 99'
    assert_equal "ACK [50@0] {move} song doesn't exist: \"99\"\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.size
    lines.each_with_index do |l,i|
      assert /^#{i}:Shpongle\/Are_You_Shpongled\/#{i+1}/ =~ l
    end

    @sock.puts 'move 1 7'
    assert_equal "ACK [50@0] {move} song doesn't exist: \"7\"\n", @sock.gets

    @sock.puts 'move 2 -3'
    assert_equal "ACK [50@0] {move} song doesn't exist: \"-3\"\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.size
    lines.each_with_index do |l,i|
      assert /^#{i}:Shpongle\/Are_You_Shpongled\/#{i+1}/ =~ l
    end

    # Test correct usage
    @sock.puts 'move 0 0'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.size
    lines.each_with_index do |l,i|
      assert /^#{i}:Shpongle\/Are_You_Shpongled\/#{i+1}/ =~ l
    end

    @sock.puts 'move 0 1'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.size
    assert_equal '0:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', lines[0]
    assert_equal '1:Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', lines[1]
    assert_equal '2:Shpongle/Are_You_Shpongled/3.Vapour_Rumours.ogg', lines[2]

    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Shpongle_-_Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'move 0 6'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.size
    assert_equal '0:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', lines[0]
    assert_equal '5:Shpongle/Are_You_Shpongled/7...._and_the_Day_Turned_to_Night.ogg', lines[5]
    assert_equal '6:Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', lines[6]

    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Shpongle_-_Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'move 5 2'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.size
    assert_equal '1:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', lines[1]
    assert_equal '2:Shpongle/Are_You_Shpongled/6.Divine_Moments_of_Truth.ogg', lines[2]
    assert_equal '3:Shpongle/Are_You_Shpongled/3.Vapour_Rumours.ogg', lines[3]
    assert_equal '4:Shpongle/Are_You_Shpongled/4.Shpongle_Spores.ogg', lines[4]
    assert_equal '5:Shpongle/Are_You_Shpongled/5.Behind_Closed_Eyelids.ogg', lines[5]
    assert_equal '6:Shpongle/Are_You_Shpongled/7...._and_the_Day_Turned_to_Night.ogg', lines[6]
  end

  def test_moveid
    @sock.gets

    # Test args = 0
    @sock.puts 'moveid'
    assert_equal "ACK [2@0] {moveid} wrong number of arguments for \"moveid\"\n", @sock.gets

    # Test args > 2
    @sock.puts 'moveid 1 2 3'
    assert_equal "ACK [2@0] {moveid} wrong number of arguments for \"moveid\"\n", @sock.gets

    # Test args not ints
    @sock.puts 'moveid a 2'
    assert_equal "ACK [2@0] {moveid} \"a\" is not a integer\n", @sock.gets

    @sock.puts 'moveid 1 b'
    assert_equal "ACK [2@0] {moveid} \"b\" is not a integer\n", @sock.gets

    # Load some songs
    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    # Test id doesn't exist
    @sock.puts 'moveid 9999 2'
    assert_equal "ACK [50@0] {moveid} song id doesn't exist: \"9999\"\n", @sock.gets

    # Test 'to' doesn't exist
    @sock.puts 'moveid 8 8'
    assert_equal "ACK [50@0] {moveid} song doesn't exist: \"8\"\n", @sock.gets

    @sock.puts 'moveid 8 5'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.size
    assert_equal '0:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[0]
    assert_equal '1:Astral_Projection/Dancing_Galaxy/3.Flying_Into_A_Star.ogg', lines[1]
    assert_equal '4:Astral_Projection/Dancing_Galaxy/6.Life_On_Mars.ogg', lines[4]
    assert_equal '5:Astral_Projection/Dancing_Galaxy/2.Soundform.ogg', lines[5]
    assert_equal '6:Astral_Projection/Dancing_Galaxy/7.Liquid_Sun.ogg', lines[6]

    @sock.puts 'moveid 12 1'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.size
    assert_equal '0:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[0]
    assert_equal '1:Astral_Projection/Dancing_Galaxy/6.Life_On_Mars.ogg', lines[1]
    assert_equal '2:Astral_Projection/Dancing_Galaxy/3.Flying_Into_A_Star.ogg', lines[2]
    assert_equal '3:Astral_Projection/Dancing_Galaxy/4.No_One_Ever_Dreams.ogg', lines[3]
    assert_equal '4:Astral_Projection/Dancing_Galaxy/5.Cosmic_Ascension_(ft._DJ_Jorg).ogg', lines[4]
    assert_equal '5:Astral_Projection/Dancing_Galaxy/2.Soundform.ogg', lines[5]
    assert_equal '6:Astral_Projection/Dancing_Galaxy/7.Liquid_Sun.ogg', lines[6]
    assert_equal '7:Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', lines[7]
  end

  def test_next
    @sock.gets

    # Test with too many args
    @sock.puts 'next 1'
    assert_equal "ACK [2@0] {next} wrong number of arguments for \"next\"\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    # Shouldn't do anything
    @sock.puts 'next'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'next'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'play'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_equal 'play', status['state']

    @sock.puts 'next'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal '1', status['song']
    assert_equal '8', status['songid']
    assert_equal 'play', status['state']

    @sock.puts 'pause'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'next'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal '2', status['song']
    assert_equal '9', status['songid']
    assert_equal 'play', status['state']

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'next'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 9, status.size
    assert_equal '2', status['song']
    assert_equal '9', status['songid']
    assert_equal 'stop', status['state']

    @sock.puts 'play'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal '2', status['song']
    assert_equal '9', status['songid']
    assert_equal 'play', status['state']

    @sock.puts 'play 7'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'next'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 7, status.size
    assert_equal 'stop', status['state']
  end

  def test_pause
    @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'play'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']

    # Test too many args
    @sock.puts 'pause 1 2'
    assert_equal "ACK [2@0] {pause} wrong number of arguments for \"pause\"\n", @sock.gets

    # Test arg NaN
    @sock.puts 'pause a'
    assert_equal "ACK [2@0] {pause} \"a\" is not 0 or 1\n", @sock.gets

    # Test int args
    @sock.puts 'pause 1'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'pause', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_not_nil status['time']
    time = status['time']

    sleep 5

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal time, status['time']

    @sock.puts 'pause 0'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_not_nil status['time']
    assert_not_equal time, status['time']

    # Test no args
    @sock.puts 'pause'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'pause', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_not_nil status['time']
    time = status['time']

    @sock.puts 'pause'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_not_nil status['time']
    assert_not_equal time, status['time']

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 9, status.size
    assert_equal 'stop', status['state']

    @sock.puts 'pause 1'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 9, status.size
    assert_equal 'stop', status['state']

    @sock.puts 'pause 0'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 9, status.size
    assert_equal 'stop', status['state']

    @sock.puts 'pause'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 9, status.size
    assert_equal 'stop', status['state']
  end

  def test_password
    @sock.gets

    @sock.puts 'password'
    assert_equal "ACK [2@0] {password} wrong number of arguments for \"password\"\n", @sock.gets

    @sock.puts 'password test'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'password wrong'
    assert_equal "ACK [3@0] {password} incorrect password\n", @sock.gets
  end

  def test_ping
    @sock.gets

    # Test ping w/ args
    @sock.puts 'ping blah'
    assert_equal "ACK [2@0] {ping} wrong number of arguments for \"ping\"\n", @sock.gets

    # Test ping
    @sock.puts 'ping'
    assert_equal "OK\n", @sock.gets
  end

  def test_play
    @sock.gets

    # Test play w/ args > 1
    @sock.puts 'play 1 2'
    assert_equal "ACK [2@0] {play} wrong number of arguments for \"play\"\n", @sock.gets
    
    # Test play w/ arg != integer
    @sock.puts 'play a'
    assert_equal "ACK [2@0] {play} need a positive integer\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    # Test play w/o args
    @sock.puts 'play'
    assert_equal "OK\n", @sock.gets

    # Wait for the thing to start playing
    sleep 2
    
    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.length
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_equal 'play', status['state']
    assert_not_nil status['time']
    assert_not_equal '0', status['time']
    assert_equal '44100:16:2', status['audio']
    assert_equal '192', status['bitrate']

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    # Test play w/ args
    @sock.puts 'play 2'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.length
    assert_equal '2', status['song']
    assert_equal '9', status['songid']
    assert_equal 'play', status['state']
    assert_not_nil status['time']
    assert_not_equal '0', status['time']
    assert_equal '44100:16:2', status['audio']
    assert_equal '192', status['bitrate']

    sleep 10

    # Check that play doesn't start over if issued during playback
    @sock.puts 'play'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.length
    assert_not_nil status['time']
    assert status['time'].to_i > 10
    assert_equal '2', status['song']
    assert_equal '9', status['songid']
    assert_equal '44100:16:2', status['audio']
    assert_equal '192', status['bitrate']

    # Test play w/ arg > length
    @sock.puts 'play 99'
    assert_equal "ACK [50@0] {play} song doesn't exist: \"99\"\n", @sock.gets
  end

  def test_playid
    @sock.gets

    # Test playid w/ args > 1
    @sock.puts 'playid 1 2'
    assert_equal "ACK [2@0] {playid} wrong number of arguments for \"playid\"\n", @sock.gets
    
    # Test playid w/ arg != integer
    @sock.puts 'playid a'
    assert_equal "ACK [2@0] {playid} need a positive integer\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    # Test playid w/o args
    @sock.puts 'playid'
    assert_equal "OK\n", @sock.gets

    # Wait for the thing to start playing
    sleep 2
    
    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.length
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_equal 'play', status['state']
    assert_not_nil status['time']
    assert_not_equal '0', status['time']
    assert_equal '44100:16:2', status['audio']
    assert_equal '192', status['bitrate']

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    # Test playid w/ args
    @sock.puts 'playid 12'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.length
    assert_equal '5', status['song']
    assert_equal '12', status['songid']
    assert_equal 'play', status['state']
    assert_not_nil status['time']
    assert_not_equal '0', status['time']
    assert_equal '44100:16:2', status['audio']
    assert_equal '192', status['bitrate']

    sleep 10

    # Check that play doesn't start over if issued during playback
    @sock.puts 'playid'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.length
    assert_not_nil status['time']
    assert status['time'].to_i > 10
    assert_equal '5', status['song']
    assert_equal '12', status['songid']
    assert_equal '44100:16:2', status['audio']
    assert_equal '192', status['bitrate']

    # Test playid w/ arg > length
    @sock.puts 'playid 99'
    assert_equal "ACK [50@0] {playid} song id doesn't exist: \"99\"\n", @sock.gets
  end

  def test_playlist
    @sock.gets

    # Test with args
    @sock.puts 'playlist blah'
    assert_equal "ACK [2@0] {playlist} wrong number of arguments for \"playlist\"\n", @sock.gets

    # Test w/o args
    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Shpongle_-_Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.length
    assert_equal '0:Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', lines[0]
    assert_equal '1:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg', lines[1]
    assert_equal '2:Shpongle/Are_You_Shpongled/3.Vapour_Rumours.ogg', lines[2]
    assert_equal '3:Shpongle/Are_You_Shpongled/4.Shpongle_Spores.ogg', lines[3]
    assert_equal '4:Shpongle/Are_You_Shpongled/5.Behind_Closed_Eyelids.ogg', lines[4]
    assert_equal '5:Shpongle/Are_You_Shpongled/6.Divine_Moments_of_Truth.ogg', lines[5]
    assert_equal '6:Shpongle/Are_You_Shpongled/7...._and_the_Day_Turned_to_Night.ogg', lines[6]
  end

  def test_playlistinfo
    @sock.gets

    # Test with too many args
    @sock.puts 'playlistinfo blah blah'
    assert_equal "ACK [2@0] {playlistinfo} wrong number of arguments for \"playlistinfo\"\n", @sock.gets

    # Test with no args
    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlistinfo'
    songs = build_songs get_response
    assert_equal 8, songs.length

    songs.each_with_index do |s,i|
      assert s['file'] =~ /^Astral_Projection\/Dancing_Galaxy\//
      assert_equal 'Astral Projection', s['Artist']
      assert_equal 'Dancing Galaxy', s['Album']
      assert_not_nil s['Title']
      assert_not_nil s['Time']
      assert_equal (i+1).to_s, s['Track']
      assert_equal (i+7).to_s, s['Id']
      assert_equal (i).to_s, s['Pos']
    end

    # Test with arg > pls length
    @sock.puts 'playlistinfo 900'
    assert_equal "ACK [50@0] {playlistinfo} song doesn't exist: \"900\"\n", @sock.gets

    # Test with arg < 0
    @sock.puts 'playlistinfo -10'
    songs = build_songs get_response
    assert_equal 8, songs.length

    songs.each_with_index do |s,i|
      assert s['file'] =~ /^Astral_Projection\/Dancing_Galaxy\//
      assert_equal 'Astral Projection', s['Artist']
      assert_equal 'Dancing Galaxy', s['Album']
      assert_not_nil s['Title']
      assert_not_nil s['Time']
      assert_equal (i+1).to_s, s['Track']
      assert_equal (i+7).to_s, s['Id']
      assert_equal (i).to_s, s['Pos']
    end
    
    #Test with valid arg
    @sock.puts 'playlistinfo 3'
    songs = build_songs get_response
    assert_equal 1, songs.length
    assert_equal 'Astral_Projection/Dancing_Galaxy/4.No_One_Ever_Dreams.ogg', songs[0]['file']
    assert_equal 'Astral Projection', songs[0]['Artist']
    assert_equal 'Dancing Galaxy', songs[0]['Album']
    assert_equal 'No One Ever Dreams', songs[0]['Title']
    assert_equal '505', songs[0]['Time']
    assert_equal '4', songs[0]['Track']
    assert_equal '10', songs[0]['Id']
    assert_equal '3', songs[0]['Pos']
  end

  def test_playlistid
    @sock.gets

    # Test with too many args
    @sock.puts 'playlistid blah blah'
    assert_equal "ACK [2@0] {playlistid} wrong number of arguments for \"playlistid\"\n", @sock.gets

    # Test with no args
    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlistid'
    songs = build_songs get_response
    assert_equal 8, songs.length

    songs.each_with_index do |s,i|
      assert s['file'] =~ /^Astral_Projection\/Dancing_Galaxy\//
      assert_equal 'Astral Projection', s['Artist']
      assert_equal 'Dancing Galaxy', s['Album']
      assert_not_nil s['Title']
      assert_not_nil s['Time']
      assert_equal (i+1).to_s, s['Track']
      assert_equal (i+7).to_s, s['Id']
      assert_equal (i).to_s, s['Pos']
    end

    # Test with arg doesn't exist 
    @sock.puts 'playlistid 900'
    assert_equal "ACK [50@0] {playlistid} song id doesn't exist: \"900\"\n", @sock.gets

    # Test with arg < 0
    @sock.puts 'playlistid -10'
    songs = build_songs get_response
    assert_equal 8, songs.length

    songs.each_with_index do |s,i|
      assert s['file'] =~ /^Astral_Projection\/Dancing_Galaxy\//
      assert_equal 'Astral Projection', s['Artist']
      assert_equal 'Dancing Galaxy', s['Album']
      assert_not_nil s['Title']
      assert_not_nil s['Time']
      assert_equal (i+1).to_s, s['Track']
      assert_equal (i+7).to_s, s['Id']
      assert_equal (i).to_s, s['Pos']
    end
    
    #Test with valid arg
    @sock.puts 'playlistid 10'
    songs = build_songs get_response
    assert_equal 1, songs.length
    assert_equal 'Astral_Projection/Dancing_Galaxy/4.No_One_Ever_Dreams.ogg', songs[0]['file']
    assert_equal 'Astral Projection', songs[0]['Artist']
    assert_equal 'Dancing Galaxy', songs[0]['Album']
    assert_equal 'No One Ever Dreams', songs[0]['Title']
    assert_equal '505', songs[0]['Time']
    assert_equal '4', songs[0]['Track']
    assert_equal '10', songs[0]['Id']
    assert_equal '3', songs[0]['Pos']
  end

  def test_plchanges
    @sock.gets

    # Test args = 0
    @sock.puts 'plchanges'
    assert_equal "ACK [2@0] {plchanges} wrong number of arguments for \"plchanges\"\n", @sock.gets

    # Test args > 1
    @sock.puts 'plchanges 1 2'
    assert_equal "ACK [2@0] {plchanges} wrong number of arguments for \"plchanges\"\n", @sock.gets

    # Test arg not integer
    @sock.puts 'plchanges a'
    assert_equal "ACK [2@0] {plchanges} need a positive integer\n", @sock.gets

    # Add some stuff to manipulate
    @sock.puts 'add Shpongle/Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '8', status['playlist']
    assert_equal '7', status['playlistlength']

    @sock.puts 'plchanges 7'
    songs = build_songs get_response
    assert_equal 1, songs.size
    assert_equal '... and the Day Turned to Night', songs[0]['Title']
    assert_equal '6', songs[0]['Pos']

    @sock.puts 'plchanges 6'
    songs = build_songs get_response
    assert_equal 2, songs.size
    assert_equal 'Divine Moments of Truth', songs[0]['Title']
    assert_equal '5', songs[0]['Pos']
    assert_equal '... and the Day Turned to Night', songs[1]['Title']
    assert_equal '6', songs[1]['Pos']

    @sock.puts 'delete 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '9', status['playlist']
    assert_equal '6', status['playlistlength']

    @sock.puts 'plchanges 8'
    songs = build_songs get_response
    assert_equal 3, songs.size
    assert_equal 'Behind Closed Eyelids', songs[0]['Title']
    assert_equal '3', songs[0]['Pos']
    assert_equal 'Divine Moments of Truth', songs[1]['Title']
    assert_equal '4', songs[1]['Pos']
    assert_equal '... and the Day Turned to Night', songs[2]['Title']
    assert_equal '5', songs[2]['Pos']

    @sock.puts 'plchanges 5'
    songs = build_songs get_response
    assert_equal 3, songs.size
    assert_equal 'Behind Closed Eyelids', songs[0]['Title']
    assert_equal '3', songs[0]['Pos']
    assert_equal 'Divine Moments of Truth', songs[1]['Title']
    assert_equal '4', songs[1]['Pos']
    assert_equal '... and the Day Turned to Night', songs[2]['Title']
    assert_equal '5', songs[2]['Pos']

    @sock.puts 'deleteid 1'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '10', status['playlist']
    assert_equal '5', status['playlistlength']

    @sock.puts 'plchanges 9'
    songs = build_songs get_response
    assert_equal 4, songs.size
    assert_equal 'Vapour Rumours', songs[0]['Title']
    assert_equal '1', songs[0]['Pos']
    assert_equal 'Behind Closed Eyelids', songs[1]['Title']
    assert_equal '2', songs[1]['Pos']
    assert_equal 'Divine Moments of Truth', songs[2]['Title']
    assert_equal '3', songs[2]['Pos']
    assert_equal '... and the Day Turned to Night', songs[3]['Title']
    assert_equal '4', songs[3]['Pos']

    @sock.puts 'plchanges 8'
    songs = build_songs get_response
    assert_equal 4, songs.size
    assert_equal 'Vapour Rumours', songs[0]['Title']
    assert_equal '1', songs[0]['Pos']
    assert_equal 'Behind Closed Eyelids', songs[1]['Title']
    assert_equal '2', songs[1]['Pos']
    assert_equal 'Divine Moments of Truth', songs[2]['Title']
    assert_equal '3', songs[2]['Pos']
    assert_equal '... and the Day Turned to Night', songs[3]['Title']
    assert_equal '4', songs[3]['Pos']

    @sock.puts 'move 1 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '11', status['playlist']
    assert_equal '5', status['playlistlength']

    @sock.puts 'plchanges 10'
    songs = build_songs get_response
    assert_equal 3, songs.size
    assert_equal 'Behind Closed Eyelids', songs[0]['Title']
    assert_equal '1', songs[0]['Pos']
    assert_equal 'Divine Moments of Truth', songs[1]['Title']
    assert_equal '2', songs[1]['Pos']
    assert_equal 'Vapour Rumours', songs[2]['Title']
    assert_equal '3', songs[2]['Pos']

    @sock.puts 'move 4 2'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '12', status['playlist']
    assert_equal '5', status['playlistlength']

    @sock.puts 'plchanges 11'
    songs = build_songs get_response
    assert_equal 3, songs.size
    assert_equal '... and the Day Turned to Night', songs[0]['Title']
    assert_equal '2', songs[0]['Pos']
    assert_equal 'Divine Moments of Truth', songs[1]['Title']
    assert_equal '3', songs[1]['Pos']
    assert_equal 'Vapour Rumours', songs[2]['Title']
    assert_equal '4', songs[2]['Pos']

    @sock.puts 'move 3 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '13', status['playlist']
    assert_equal '5', status['playlistlength']

    @sock.puts 'plchanges 12'
    songs = build_songs get_response
    assert_equal 1, songs.size
    assert_equal 'Divine Moments of Truth', songs[0]['Title']
    assert_equal '3', songs[0]['Pos']

    # load test
    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '22', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchanges 21'
    songs = build_songs get_response
    assert_equal 1, songs.size
    assert_equal 'Ambient Galaxy (Disco Valley Mix)', songs[0]['Title']
    assert_equal '7', songs[0]['Pos']

    @sock.puts 'plchanges 18'
    songs = build_songs get_response
    assert_equal 4, songs.size
    assert_equal 'Cosmic Ascension (ft. DJ Jorg)', songs[0]['Title']
    assert_equal '4', songs[0]['Pos']
    assert_equal 'Life On Mars', songs[1]['Title']
    assert_equal '5', songs[1]['Pos']
    assert_equal 'Liquid Sun', songs[2]['Title']
    assert_equal '6', songs[2]['Pos']
    assert_equal 'Ambient Galaxy (Disco Valley Mix)', songs[3]['Title']
    assert_equal '7', songs[3]['Pos']

    # moveid test
    @sock.puts 'moveid 8 5'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '23', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchanges 22'
    songs = build_songs get_response
    assert_equal 5, songs.size
    assert_equal 'Flying Into A Star', songs[0]['Title']
    assert_equal '1', songs[0]['Pos']
    assert_equal 'No One Ever Dreams', songs[1]['Title']
    assert_equal '2', songs[1]['Pos']
    assert_equal 'Cosmic Ascension (ft. DJ Jorg)', songs[2]['Title']
    assert_equal '3', songs[2]['Pos']
    assert_equal 'Life On Mars', songs[3]['Title']
    assert_equal '4', songs[3]['Pos']
    assert_equal 'Soundform', songs[4]['Title']
    assert_equal '5', songs[4]['Pos']

    @sock.puts 'moveid 12 1'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '24', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchanges 23'
    songs = build_songs get_response
    assert_equal 4, songs.size
    assert_equal 'Life On Mars', songs[0]['Title']
    assert_equal '1', songs[0]['Pos']
    assert_equal 'Flying Into A Star', songs[1]['Title']
    assert_equal '2', songs[1]['Pos']
    assert_equal 'No One Ever Dreams', songs[2]['Title']
    assert_equal '3', songs[2]['Pos']
    assert_equal 'Cosmic Ascension (ft. DJ Jorg)', songs[3]['Title']
    assert_equal '4', songs[3]['Pos']

    @sock.puts 'plchanges 22'
    songs = build_songs get_response
    assert_equal 5, songs.size
    assert_equal 'Life On Mars', songs[0]['Title']
    assert_equal '1', songs[0]['Pos']
    assert_equal 'Flying Into A Star', songs[1]['Title']
    assert_equal '2', songs[1]['Pos']
    assert_equal 'No One Ever Dreams', songs[2]['Title']
    assert_equal '3', songs[2]['Pos']
    assert_equal 'Cosmic Ascension (ft. DJ Jorg)', songs[3]['Title']
    assert_equal '4', songs[3]['Pos']
    assert_equal 'Soundform', songs[4]['Title']
    assert_equal '5', songs[4]['Pos']

    @sock.puts 'swap 2 5'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '25', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchanges 24'
    songs = build_songs get_response
    assert_equal 2, songs.size
    assert_equal 'Soundform', songs[0]['Title']
    assert_equal '2', songs[0]['Pos']
    assert_equal 'Flying Into A Star', songs[1]['Title']
    assert_equal '5', songs[1]['Pos']

    @sock.puts 'swap 7 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '26', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchanges 25'
    songs = build_songs get_response
    assert_equal 2, songs.size
    assert_equal 'Ambient Galaxy (Disco Valley Mix)', songs[0]['Title']
    assert_equal '3', songs[0]['Pos']
    assert_equal 'No One Ever Dreams', songs[1]['Title']
    assert_equal '7', songs[1]['Pos']

    @sock.puts 'plchanges 24'
    songs = build_songs get_response
    assert_equal 4, songs.size
    assert_equal 'Soundform', songs[0]['Title']
    assert_equal '2', songs[0]['Pos']
    assert_equal 'Ambient Galaxy (Disco Valley Mix)', songs[1]['Title']
    assert_equal '3', songs[1]['Pos']
    assert_equal 'Flying Into A Star', songs[2]['Title']
    assert_equal '5', songs[2]['Pos']
    assert_equal 'No One Ever Dreams', songs[3]['Title']
    assert_equal '7', songs[3]['Pos']

    @sock.puts 'swapid 7 13'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '27', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchanges 26'
    songs = build_songs get_response
    assert_equal 2, songs.size
    assert_equal 'Liquid Sun', songs[0]['Title']
    assert_equal '0', songs[0]['Pos']
    assert_equal 'Dancing Galaxy', songs[1]['Title']
    assert_equal '6', songs[1]['Pos']

    @sock.puts 'swapid 11 12'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '28', status['playlist']
    assert_equal '8', status['playlistlength']
    
    @sock.puts 'plchanges 27'
    songs = build_songs get_response
    assert_equal 2, songs.size
    assert_equal 'Cosmic Ascension (ft. DJ Jorg)', songs[0]['Title']
    assert_equal '1', songs[0]['Pos']
    assert_equal 'Life On Mars', songs[1]['Title']
    assert_equal '4', songs[1]['Pos']

    @sock.puts 'plchanges 26'
    songs = build_songs get_response
    assert_equal 4, songs.size
    assert_equal 'Liquid Sun', songs[0]['Title']
    assert_equal '0', songs[0]['Pos']
    assert_equal 'Cosmic Ascension (ft. DJ Jorg)', songs[1]['Title']
    assert_equal '1', songs[1]['Pos']
    assert_equal 'Life On Mars', songs[2]['Title']
    assert_equal '4', songs[2]['Pos']
    assert_equal 'Dancing Galaxy', songs[3]['Title']
    assert_equal '6', songs[3]['Pos']

    @sock.puts 'shuffle'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '29', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchanges 28'
    songs = build_songs get_response
    assert_equal 8, songs.size
    assert_equal 'No One Ever Dreams', songs[0]['Title']
    assert_equal '0', songs[0]['Pos']
    assert_equal 'Dancing Galaxy', songs[1]['Title']
    assert_equal '1', songs[1]['Pos']
    assert_equal 'Flying Into A Star', songs[2]['Title']
    assert_equal '2', songs[2]['Pos']
    assert_equal 'Life On Mars', songs[3]['Title']
    assert_equal '3', songs[3]['Pos']
    assert_equal 'Ambient Galaxy (Disco Valley Mix)', songs[4]['Title']
    assert_equal '4', songs[4]['Pos']
    assert_equal 'Soundform', songs[5]['Title']
    assert_equal '5', songs[5]['Pos']
    assert_equal 'Cosmic Ascension (ft. DJ Jorg)', songs[6]['Title']
    assert_equal '6', songs[6]['Pos']
    assert_equal 'Liquid Sun', songs[7]['Title']
    assert_equal '7', songs[7]['Pos']

    @sock.puts 'add Shpongle/Are_You_Shpongled/6.Divine_Moments_of_Truth.ogg'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '30', status['playlist']
    assert_equal '9', status['playlistlength']
    
    @sock.puts 'plchanges 29'
    songs = build_songs get_response
    assert_equal 1, songs.size
    assert_equal 'Divine Moments of Truth', songs[0]['Title']
    assert_equal '8', songs[0]['Pos']
  end

  def test_plchangesposid
    @sock.gets

    # Test args = 0
    @sock.puts 'plchangesposid'
    assert_equal "ACK [2@0] {plchangesposid} wrong number of arguments for \"plchangesposid\"\n", @sock.gets

    # Test args > 1
    @sock.puts 'plchangesposid 1 2'
    assert_equal "ACK [2@0] {plchangesposid} wrong number of arguments for \"plchangesposid\"\n", @sock.gets

    # Test arg not integer
    @sock.puts 'plchangesposid a'
    assert_equal "ACK [2@0] {plchangesposid} need a positive integer\n", @sock.gets

    # Add some stuff to manipulate
    @sock.puts 'add Shpongle/Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '8', status['playlist']
    assert_equal '7', status['playlistlength']

    @sock.puts 'plchangesposid 7'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 2, songs.size
    assert_equal 'cpos: 6', songs[0]
    assert_equal 'Id: 6', songs[1]

    @sock.puts 'plchangesposid 6'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 4, songs.size
    assert_equal 'cpos: 5', songs[0]
    assert_equal 'Id: 5', songs[1]
    assert_equal 'cpos: 6', songs[2]
    assert_equal 'Id: 6', songs[3]

    @sock.puts 'delete 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '9', status['playlist']
    assert_equal '6', status['playlistlength']

    @sock.puts 'plchangesposid 8'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 6, songs.size
    assert_equal 'cpos: 3', songs[0]
    assert_equal 'Id: 4', songs[1]
    assert_equal 'cpos: 4', songs[2]
    assert_equal 'Id: 5', songs[3]
    assert_equal 'cpos: 5', songs[4]
    assert_equal 'Id: 6', songs[5]

    @sock.puts 'plchangesposid 5'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 6, songs.size
    assert_equal 'cpos: 3', songs[0]
    assert_equal 'Id: 4', songs[1]
    assert_equal 'cpos: 4', songs[2]
    assert_equal 'Id: 5', songs[3]
    assert_equal 'cpos: 5', songs[4]
    assert_equal 'Id: 6', songs[5]

    @sock.puts 'deleteid 1'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '10', status['playlist']
    assert_equal '5', status['playlistlength']

    @sock.puts 'plchangesposid 9'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 8, songs.size
    assert_equal 'cpos: 1', songs[0]
    assert_equal 'Id: 2', songs[1]
    assert_equal 'cpos: 2', songs[2]
    assert_equal 'Id: 4', songs[3]
    assert_equal 'cpos: 3', songs[4]
    assert_equal 'Id: 5', songs[5]
    assert_equal 'cpos: 4', songs[6]
    assert_equal 'Id: 6', songs[7]

    @sock.puts 'plchangesposid 8'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 8, songs.size
    assert_equal 'cpos: 1', songs[0]
    assert_equal 'Id: 2', songs[1]
    assert_equal 'cpos: 2', songs[2]
    assert_equal 'Id: 4', songs[3]
    assert_equal 'cpos: 3', songs[4]
    assert_equal 'Id: 5', songs[5]
    assert_equal 'cpos: 4', songs[6]
    assert_equal 'Id: 6', songs[7]

    @sock.puts 'move 1 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '11', status['playlist']
    assert_equal '5', status['playlistlength']

    @sock.puts 'plchangesposid 10'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 6, songs.size
    assert_equal 'cpos: 1', songs[0]
    assert_equal 'Id: 4', songs[1]
    assert_equal 'cpos: 2', songs[2]
    assert_equal 'Id: 5', songs[3]
    assert_equal 'cpos: 3', songs[4]
    assert_equal 'Id: 2', songs[5]

    @sock.puts 'move 4 2'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '12', status['playlist']
    assert_equal '5', status['playlistlength']

    @sock.puts 'plchangesposid 11'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 6, songs.size
    assert_equal 'cpos: 2', songs[0]
    assert_equal 'Id: 6', songs[1]
    assert_equal 'cpos: 3', songs[2]
    assert_equal 'Id: 5', songs[3]
    assert_equal 'cpos: 4', songs[4]
    assert_equal 'Id: 2', songs[5]

    @sock.puts 'move 3 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '13', status['playlist']
    assert_equal '5', status['playlistlength']

    @sock.puts 'plchangesposid 12'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 2, songs.size
    assert_equal 'cpos: 3', songs[0]
    assert_equal 'Id: 5', songs[1]

    # load test
    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '22', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchangesposid 21'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 2, songs.size
    assert_equal 'cpos: 7', songs[0]
    assert_equal 'Id: 14', songs[1]

    @sock.puts 'plchangesposid 18'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 8, songs.size
    assert_equal 'cpos: 4', songs[0]
    assert_equal 'Id: 11', songs[1]
    assert_equal 'cpos: 5', songs[2]
    assert_equal 'Id: 12', songs[3]
    assert_equal 'cpos: 6', songs[4]
    assert_equal 'Id: 13', songs[5]
    assert_equal 'cpos: 7', songs[6]
    assert_equal 'Id: 14', songs[7]

    # moveid test
    @sock.puts 'moveid 8 5'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '23', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchangesposid 22'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 10, songs.size
    assert_equal 'cpos: 1', songs[0]
    assert_equal 'Id: 9', songs[1]
    assert_equal 'cpos: 2', songs[2]
    assert_equal 'Id: 10', songs[3]
    assert_equal 'cpos: 3', songs[4]
    assert_equal 'Id: 11', songs[5]
    assert_equal 'cpos: 4', songs[6]
    assert_equal 'Id: 12', songs[7]
    assert_equal 'cpos: 5', songs[8]
    assert_equal 'Id: 8', songs[9]

    @sock.puts 'moveid 12 1'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '24', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchangesposid 23'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 8, songs.size
    assert_equal 'cpos: 1', songs[0]
    assert_equal 'Id: 12', songs[1]
    assert_equal 'cpos: 2', songs[2]
    assert_equal 'Id: 9', songs[3]
    assert_equal 'cpos: 3', songs[4]
    assert_equal 'Id: 10', songs[5]
    assert_equal 'cpos: 4', songs[6]
    assert_equal 'Id: 11', songs[7]

    @sock.puts 'plchangesposid 22'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 10, songs.size
    assert_equal 'cpos: 1', songs[0]
    assert_equal 'Id: 12', songs[1]
    assert_equal 'cpos: 2', songs[2]
    assert_equal 'Id: 9', songs[3]
    assert_equal 'cpos: 3', songs[4]
    assert_equal 'Id: 10', songs[5]
    assert_equal 'cpos: 4', songs[6]
    assert_equal 'Id: 11', songs[7]
    assert_equal 'cpos: 5', songs[8]
    assert_equal 'Id: 8', songs[9]

    @sock.puts 'swap 2 5'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '25', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchangesposid 24'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 4, songs.size
    assert_equal 'cpos: 2', songs[0]
    assert_equal 'Id: 8', songs[1]
    assert_equal 'cpos: 5', songs[2]
    assert_equal 'Id: 9', songs[3]

    @sock.puts 'swap 7 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '26', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchangesposid 25'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 4, songs.size
    assert_equal 'cpos: 3', songs[0]
    assert_equal 'Id: 14', songs[1]
    assert_equal 'cpos: 7', songs[2]
    assert_equal 'Id: 10', songs[3]

    @sock.puts 'plchangesposid 24'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 8, songs.size
    assert_equal 'cpos: 2', songs[0]
    assert_equal 'Id: 8', songs[1]
    assert_equal 'cpos: 3', songs[2]
    assert_equal 'Id: 14', songs[3]
    assert_equal 'cpos: 5', songs[4]
    assert_equal 'Id: 9', songs[5]
    assert_equal 'cpos: 7', songs[6]
    assert_equal 'Id: 10', songs[7]

    @sock.puts 'swapid 7 13'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '27', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchangesposid 26'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 4, songs.size
    assert_equal 'cpos: 0', songs[0]
    assert_equal 'Id: 13', songs[1]
    assert_equal 'cpos: 6', songs[2]
    assert_equal 'Id: 7', songs[3]

    @sock.puts 'swapid 11 12'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '28', status['playlist']
    assert_equal '8', status['playlistlength']
    
    @sock.puts 'plchangesposid 27'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 4, songs.size
    assert_equal 'cpos: 1', songs[0]
    assert_equal 'Id: 11', songs[1]
    assert_equal 'cpos: 4', songs[2]
    assert_equal 'Id: 12', songs[3]

    @sock.puts 'plchangesposid 26'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 8, songs.size
    assert_equal 'cpos: 0', songs[0]
    assert_equal 'Id: 13', songs[1]
    assert_equal 'cpos: 1', songs[2]
    assert_equal 'Id: 11', songs[3]
    assert_equal 'cpos: 4', songs[4]
    assert_equal 'Id: 12', songs[5]
    assert_equal 'cpos: 6', songs[6]
    assert_equal 'Id: 7', songs[7]

    @sock.puts 'shuffle'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '29', status['playlist']
    assert_equal '8', status['playlistlength']

    @sock.puts 'plchangesposid 28'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 16, songs.size
    assert_equal 'cpos: 0', songs[0]
    assert_equal 'Id: 10', songs[1]
    assert_equal 'cpos: 1', songs[2]
    assert_equal 'Id: 7', songs[3]
    assert_equal 'cpos: 2', songs[4]
    assert_equal 'Id: 9', songs[5]
    assert_equal 'cpos: 3', songs[6]
    assert_equal 'Id: 12', songs[7]
    assert_equal 'cpos: 4', songs[8]
    assert_equal 'Id: 14', songs[9]
    assert_equal 'cpos: 5', songs[10]
    assert_equal 'Id: 8', songs[11]
    assert_equal 'cpos: 6', songs[12]
    assert_equal 'Id: 11', songs[13]
    assert_equal 'cpos: 7', songs[14]
    assert_equal 'Id: 13', songs[15]

    @sock.puts 'add Shpongle/Are_You_Shpongled/6.Divine_Moments_of_Truth.ogg'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '30', status['playlist']
    assert_equal '9', status['playlistlength']
    
    @sock.puts 'plchangesposid 29'
    reply = get_response
    songs = reply.split "\n"
    assert_equal 2, songs.size
    assert_equal 'cpos: 8', songs[0]
    assert_equal 'Id: 5', songs[1]
  end

  def test_previous
    @sock.gets

    # Test with too many args
    @sock.puts 'previous 1'
    assert_equal "ACK [2@0] {previous} wrong number of arguments for \"previous\"\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    # Shouldn't do anything
    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 7, status.size
    assert_equal 'stop', status['state']

    @sock.puts 'play 7'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal '6', status['song']
    assert_equal '13', status['songid']
    assert_equal 'play', status['state']

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_equal 'play', status['state']

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_equal 'play', status['state']

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'play 4'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'pause'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal '3', status['song']
    assert_equal '10', status['songid']
    assert_equal 'play', status['state']

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'play 6'
    assert_equal "OK\n", @sock.gets
    
    sleep 2

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'previous'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 9, status.size
    assert_equal 'stop', status['state']
    assert_equal '6', status['song']
    assert_equal '13', status['songid']
  end

  def test_random
    @sock.gets
    # Test no args
    @sock.puts 'random'
    assert_equal "ACK [2@0] {random} wrong number of arguments for \"random\"\n", @sock.gets

    # Test too many args
    @sock.puts 'random blah blah'
    assert_equal "ACK [2@0] {random} wrong number of arguments for \"random\"\n", @sock.gets

    # Test arg != integer
    @sock.puts 'random b'
    assert_equal "ACK [2@0] {random} need an integer\n", @sock.gets

    # Test arg != (0||1)
    @sock.puts 'random 3'
    assert_equal "ACK [2@0] {random} \"3\" is not 0 or 1\n", @sock.gets

    # Test arg < 0
    @sock.puts 'random -1'
    assert_equal "ACK [2@0] {random} \"-1\" is not 0 or 1\n", @sock.gets

    # Test disable
    @sock.puts 'random 0'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '0', status['random']

    # Test Enable
    @sock.puts 'random 1'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '1', status['random']

    @sock.puts 'random 0'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '0', status['random']
  end

  def test_repeat
    @sock.gets
    # Test no args
    @sock.puts 'repeat'
    assert_equal "ACK [2@0] {repeat} wrong number of arguments for \"repeat\"\n", @sock.gets

    # Test too many args
    @sock.puts 'repeat blah blah'
    assert_equal "ACK [2@0] {repeat} wrong number of arguments for \"repeat\"\n", @sock.gets

    # Test arg != integer
    @sock.puts 'repeat b'
    assert_equal "ACK [2@0] {repeat} need an integer\n", @sock.gets

    # Test arg != (0||1)
    @sock.puts 'repeat 3'
    assert_equal "ACK [2@0] {repeat} \"3\" is not 0 or 1\n", @sock.gets

    # Test arg < 0
    @sock.puts 'repeat -1'
    assert_equal "ACK [2@0] {repeat} \"-1\" is not 0 or 1\n", @sock.gets

    # Test disable
    @sock.puts 'repeat 0'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '0', status['repeat']

    # Test enable
    @sock.puts 'repeat 1'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '1', status['repeat']

    @sock.puts 'repeat 0'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '0', status['repeat']
  end

  def test_rm
    @sock.gets
    
    # Test no args
    @sock.puts 'rm'
    assert_equal "ACK [2@0] {rm} wrong number of arguments for \"rm\"\n", @sock.gets

    # Test args > 1
    @sock.puts 'rm 1 2'
    assert_equal "ACK [2@0] {rm} wrong number of arguments for \"rm\"\n", @sock.gets

    # Test arg not exist
    @sock.puts 'rm abomination'
    assert_equal "ACK [50@0] {rm} playlist \"abomination\" not found\n", @sock.gets

    # Test arg exists
    @sock.puts 'rm Shpongle_-_Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    # Ensure the pls was removed
    @sock.puts 'lsinfo'
    reply = get_response
    lines = reply.split "\n"
    found = false
    lines.each do |l|
      if l == 'playlist: Shpongle_-_Are_You_Shpongled'
        found = true
        break
      end
    end

    assert !found, 'The playlist was not removed'
  end

  def test_save
    @sock.gets

    # Test no args
    @sock.puts 'save'
    assert_equal "ACK [2@0] {save} wrong number of arguments for \"save\"\n", @sock.gets

    # Test args > 1
    @sock.puts 'save 1 2'
    assert_equal "ACK [2@0] {save} wrong number of arguments for \"save\"\n", @sock.gets

    @sock.puts 'load Shpongle_-_Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    # Test correct args
    @sock.puts 'save Save_Test'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'lsinfo'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 6, lines.length
    assert_equal 'directory: Astral_Projection', lines[0]
    assert_equal 'directory: Carbon_Based_Lifeforms', lines[1]
    assert_equal 'directory: Shpongle', lines[2]
    assert_equal 'playlist: Shpongle_-_Are_You_Shpongled', lines[3]
    assert_equal 'playlist: Astral_Projection_-_Dancing_Galaxy', lines[4]
    assert_equal 'playlist: Save_Test', lines[5]

    @sock.puts 'clear'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'load Save_Test'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 15, lines.length
    assert_equal '0:Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg', lines[0]
    assert_equal '3:Shpongle/Are_You_Shpongled/4.Shpongle_Spores.ogg', lines[3]
    assert_equal '6:Shpongle/Are_You_Shpongled/7...._and_the_Day_Turned_to_Night.ogg', lines[6]
    assert_equal '7:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[7]
    assert_equal '11:Astral_Projection/Dancing_Galaxy/5.Cosmic_Ascension_(ft._DJ_Jorg).ogg', lines[11]
    assert_equal '14:Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', lines[14]
  end

  def test_search
    @sock.gets

    @sock.puts 'search'
    assert_equal "ACK [2@0] {search} wrong number of arguments for \"search\"\n", @sock.gets

    @sock.puts 'search 1 2 3'
    assert_equal "ACK [2@0] {search} wrong number of arguments for \"search\"\n", @sock.gets

    @sock.puts 'search wrong Shpongle'
    assert_equal "ACK [2@0] {search} incorrect arguments\n", @sock.gets

    @sock.puts 'search artist "arbon based life"'
    songs = build_songs get_response
    assert_equal 11, songs.size
    songs.each_with_index do |song,i|
      assert_equal i+1, song['Track'].to_i
      assert_equal i+15, song['Id'].to_i
      assert_equal 'Carbon Based Lifeforms', song['Artist']
      assert_equal 'Hydroponic Garden', song['Album']
      assert song['file'] =~ /^Carbon_Based_Lifeforms\/Hydroponic_Garden\//
    end

    @sock.puts 'search album hydroponic'
    songs = build_songs get_response
    assert_equal 11, songs.size
    songs.each_with_index do |song,i|
      assert_equal i+1, song['Track'].to_i
      assert_equal i+15, song['Id'].to_i
      assert_equal 'Carbon Based Lifeforms', song['Artist']
      assert_equal 'Hydroponic Garden', song['Album']
      assert song['file'] =~ /^Carbon_Based_Lifeforms\/Hydroponic_Garden\//
    end

    @sock.puts 'search filename hydropo'
    songs = build_songs get_response
    assert_equal 11, songs.size
    songs.each_with_index do |song,i|
      assert_equal i+1, song['Track'].to_i
      assert_equal i+15, song['Id'].to_i
      assert_equal 'Carbon Based Lifeforms', song['Artist']
      assert_equal 'Hydroponic Garden', song['Album']
      assert song['file'] =~ /^Carbon_Based_Lifeforms\/Hydroponic_Garden\//
    end

    @sock.puts 'search title "silent running"'
    songs = build_songs get_response
    assert_equal 1, songs.size
    assert_equal '4', songs[0]['Track']
    assert_equal '18', songs[0]['Id']
    assert_equal 'Carbon_Based_Lifeforms/Hydroponic_Garden/04.Silent_Running.ogg', songs[0]['file']
    assert_equal 'Silent Running', songs[0]['Title']
    assert_equal 'Hydroponic Garden', songs[0]['Album']
    assert_equal 'Carbon Based Lifeforms', songs[0]['Artist']

    @sock.puts 'search title "no title"'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'search artist "no artist"'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'search album "no album"'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'search filename "no file"'
    assert_equal "OK\n", @sock.gets
  end

  def test_seek
    @sock.gets

    @sock.puts 'seek'
    assert_equal "ACK [2@0] {seek} wrong number of arguments for \"seek\"\n", @sock.gets

    @sock.puts 'seek 1 2 3'
    assert_equal "ACK [2@0] {seek} wrong number of arguments for \"seek\"\n", @sock.gets

    @sock.puts 'seek a 2'
    assert_equal "ACK [2@0] {seek} \"a\" is not a integer\n", @sock.gets

    @sock.puts 'seek 1 a'
    assert_equal "ACK [2@0] {seek} \"a\" is not a integer\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'seek 99 10'
    assert_equal "ACK [50@0] {seek} song doesn't exist: \"99\"\n", @sock.gets

    @sock.puts 'seek -1 10'
    assert_equal "ACK [50@0] {seek} song doesn't exist: \"-1\"\n", @sock.gets

    @sock.puts 'seek 0 40'
    assert_equal "OK\n", @sock.gets

    sleep 4

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_not_nil status['time']
    assert 40 < status['time'].to_i
    assert 55 > status['time'].to_i

    @sock.puts 'pause 1'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'seek 4 100'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'pause', status['state']
    assert_equal '4', status['song']
    assert_equal '11', status['songid']
    assert_equal 100, status['time'].to_i

    @sock.puts 'pause 0'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'seek 6 200'
    assert_equal "OK\n", @sock.gets
    
    sleep 4

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '6', status['song']
    assert_equal '13', status['songid']
    assert 200 < status['time'].to_i
    assert 215 > status['time'].to_i

    @sock.puts 'seek 2 10000'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '3', status['song']
    assert_equal '10', status['songid']
    assert 10 > status['time'].to_i

    @sock.puts 'seek 7 10000'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 7, status.size
    assert_equal 'stop', status['state']

    @sock.puts 'seek 2 -100'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '2', status['song']
    assert_equal '9', status['songid']
    assert 5 > status['time'].to_i
  end

  def test_seekid
    @sock.gets

    @sock.puts 'seekid'
    assert_equal "ACK [2@0] {seekid} wrong number of arguments for \"seekid\"\n", @sock.gets

    @sock.puts 'seekid 1 2 3'
    assert_equal "ACK [2@0] {seekid} wrong number of arguments for \"seekid\"\n", @sock.gets

    @sock.puts 'seekid a 2'
    assert_equal "ACK [2@0] {seekid} \"a\" is not a integer\n", @sock.gets

    @sock.puts 'seekid 1 a'
    assert_equal "ACK [2@0] {seekid} \"a\" is not a integer\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'seekid 99 10'
    assert_equal "ACK [50@0] {seekid} song id doesn't exist: \"99\"\n", @sock.gets

    @sock.puts 'seekid -1 10'
    assert_equal "ACK [50@0] {seekid} song id doesn't exist: \"-1\"\n", @sock.gets

    @sock.puts 'seekid 7 40'
    assert_equal "OK\n", @sock.gets

    sleep 4

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_not_nil status['time']
    assert 40 < status['time'].to_i
    assert 55 > status['time'].to_i

    @sock.puts 'pause 1'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'seekid 11 100'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'pause', status['state']
    assert_equal '4', status['song']
    assert_equal '11', status['songid']
    assert_equal 100, status['time'].to_i

    @sock.puts 'pause 0'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'seekid 13 200'
    assert_equal "OK\n", @sock.gets
    
    sleep 4

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '6', status['song']
    assert_equal '13', status['songid']
    assert 200 < status['time'].to_i
    assert 215 > status['time'].to_i

    @sock.puts 'seekid 9 10000'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '3', status['song']
    assert_equal '10', status['songid']
    assert 10 > status['time'].to_i

    @sock.puts 'seekid 14 10000'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 7, status.size
    assert_equal 'stop', status['state']

    @sock.puts 'seekid 9 -100'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '2', status['song']
    assert_equal '9', status['songid']
    assert 5 > status['time'].to_i
  end

  def test_setvol
    @sock.gets

    # Test no args
    @sock.puts 'setvol'
    assert_equal "ACK [2@0] {setvol} wrong number of arguments for \"setvol\"\n", @sock.gets

    # Test too many args
    @sock.puts 'setvol 1 2'
    assert_equal "ACK [2@0] {setvol} wrong number of arguments for \"setvol\"\n", @sock.gets

    # Test arg not an int
    @sock.puts 'setvol a'
    assert_equal "ACK [2@0] {setvol} need an integer\n", @sock.gets

    # Test correct arg
    @sock.puts 'setvol 0'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '0', status['volume']

    @sock.puts 'setvol 20'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '20', status['volume']

    @sock.puts 'setvol -30'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '-30', status['volume']
  end

  def test_shuffle
    @sock.gets

    @sock.puts 'load Shpongle_-_Are_You_Shpongled'
    assert_equal "OK\n", @sock.gets

    # Test args > 0
    @sock.puts 'shuffle 1'
    assert_equal "ACK [2@0] {shuffle} wrong number of arguments for \"shuffle\"\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.size
    assert_equal "0:Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg", lines[0]
    assert_equal "1:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg", lines[1]

    @sock.puts 'shuffle 1 2'
    assert_equal "ACK [2@0] {shuffle} wrong number of arguments for \"shuffle\"\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.size
    assert_equal "0:Shpongle/Are_You_Shpongled/1.Shpongle_Falls.ogg", lines[0]
    assert_equal "1:Shpongle/Are_You_Shpongled/2.Monster_Hit.ogg", lines[1]

    # Test correct usage
    @sock.puts 'shuffle'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 7, lines.size
    assert_equal "0:Shpongle/Are_You_Shpongled/7...._and_the_Day_Turned_to_Night.ogg", lines[0]
    assert_equal "1:Shpongle/Are_You_Shpongled/6.Divine_Moments_of_Truth.ogg", lines[1]
  end

  def test_stats
    @sock.gets

    # Test args > 0
    @sock.puts 'stats 1'
    assert_equal "ACK [2@0] {stats} wrong number of arguments for \"stats\"\n", @sock.gets

    @sock.puts 'stats 1 2'
    assert_equal "ACK [2@0] {stats} wrong number of arguments for \"stats\"\n", @sock.gets

    # Test correct usage
    @sock.puts 'stats'
    stats = build_hash get_response
    assert_equal 7, stats.size
    assert_equal '3', stats['artists']
    assert_equal '4', stats['albums']
    assert_equal '46', stats['songs']
    assert_equal '500', stats['uptime']
    assert_equal '18091', stats['db_playtime']
    assert_equal '1159418502', stats['db_update']
    assert_equal '10', stats['playtime']
  end

  def test_status
    @sock.gets

    # Test args > 0
    @sock.puts 'status 1'
    assert_equal "ACK [2@0] {status} wrong number of arguments for \"status\"\n", @sock.gets

    @sock.puts 'status 1 2'
    assert_equal "ACK [2@0] {status} wrong number of arguments for \"status\"\n", @sock.gets

    # Test correct usage
    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 7, status.size
    assert_equal '0', status['volume']
    assert_equal '0', status['repeat']
    assert_equal '1', status['playlist']
    assert_equal '0', status['playlistlength']
    assert_equal 'stop', status['state']

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'setvol 50'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 7, status.size
    assert_equal '50', status['volume']

    @sock.puts 'repeat 1'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 7, status.size
    assert_equal '50', status['volume']
    assert_equal '1', status['repeat']

    @sock.puts 'play'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_not_nil status['time']
    assert_equal '192', status['bitrate']
    assert_equal '44100:16:2', status['audio']

    @sock.puts 'pause 1'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'pause', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_not_nil status['time']
    assert_equal '192', status['bitrate']
    assert_equal '44100:16:2', status['audio']
    time = status['time']

    sleep 5

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal time, status['time']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']

    @sock.puts 'pause 0'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 9, status.size
    assert_equal 'stop', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_nil status['time']
    assert_nil status['bitrate']
    assert_nil status['audio']
  end

  def test_stop
    @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'play'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
    assert_not_nil status['time']
    assert_equal '192', status['bitrate']
    assert_equal '44100:16:2', status['audio']

    # Test too many args
    @sock.puts 'stop 1'
    assert_equal "ACK [2@0] {stop} wrong number of arguments for \"stop\"\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 12, status.size
    assert_equal 'play', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']

    @sock.puts 'stop'
    assert_equal "OK\n", @sock.gets

    sleep 2

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 9, status.size
    assert_equal 'stop', status['state']
    assert_equal '0', status['song']
    assert_equal '7', status['songid']
  end

  def test_swap
    @sock.gets

    # Test args = 0
    @sock.puts 'swap'
    assert_equal "ACK [2@0] {swap} wrong number of arguments for \"swap\"\n", @sock.gets

    # Test args > 2
    @sock.puts 'swap 1 2 3'
    assert_equal "ACK [2@0] {swap} wrong number of arguments for \"swap\"\n", @sock.gets

    # Test args not int
    @sock.puts 'swap a 3'
    assert_equal "ACK [2@0] {swap} \"a\" is not a integer\n", @sock.gets

    @sock.puts 'swap 1 b'
    assert_equal "ACK [2@0] {swap} \"b\" is not a integer\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    # Test args out of bounds
    @sock.puts 'swap 99 5'
    assert_equal "ACK [50@0] {swap} song doesn't exist: \"99\"\n", @sock.gets

    @sock.puts 'swap 1 99'
    assert_equal "ACK [50@0] {swap} song doesn't exist: \"99\"\n", @sock.gets

    @sock.puts 'swap -1 4'
    assert_equal "ACK [50@0] {swap} song doesn't exist: \"-1\"\n", @sock.gets

    @sock.puts 'swap 1 -4'
    assert_equal "ACK [50@0] {swap} song doesn't exist: \"-4\"\n", @sock.gets

    @sock.puts 'swap 1 5'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.size
    assert_equal '0:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[0]
    assert_equal '1:Astral_Projection/Dancing_Galaxy/6.Life_On_Mars.ogg', lines[1]
    assert_equal '2:Astral_Projection/Dancing_Galaxy/3.Flying_Into_A_Star.ogg', lines[2]
    assert_equal '3:Astral_Projection/Dancing_Galaxy/4.No_One_Ever_Dreams.ogg', lines[3]
    assert_equal '4:Astral_Projection/Dancing_Galaxy/5.Cosmic_Ascension_(ft._DJ_Jorg).ogg', lines[4]
    assert_equal '5:Astral_Projection/Dancing_Galaxy/2.Soundform.ogg', lines[5]
    assert_equal '6:Astral_Projection/Dancing_Galaxy/7.Liquid_Sun.ogg', lines[6]
    assert_equal '7:Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', lines[7]

    @sock.puts 'swap 7 3'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.size
    assert_equal '0:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[0]
    assert_equal '1:Astral_Projection/Dancing_Galaxy/6.Life_On_Mars.ogg', lines[1]
    assert_equal '2:Astral_Projection/Dancing_Galaxy/3.Flying_Into_A_Star.ogg', lines[2]
    assert_equal '3:Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', lines[3]     
    assert_equal '4:Astral_Projection/Dancing_Galaxy/5.Cosmic_Ascension_(ft._DJ_Jorg).ogg', lines[4]
    assert_equal '5:Astral_Projection/Dancing_Galaxy/2.Soundform.ogg', lines[5]
    assert_equal '6:Astral_Projection/Dancing_Galaxy/7.Liquid_Sun.ogg', lines[6]
    assert_equal '7:Astral_Projection/Dancing_Galaxy/4.No_One_Ever_Dreams.ogg', lines[7]

    @sock.puts 'swap 0 2'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.size
    assert_equal '0:Astral_Projection/Dancing_Galaxy/3.Flying_Into_A_Star.ogg', lines[0]
    assert_equal '1:Astral_Projection/Dancing_Galaxy/6.Life_On_Mars.ogg', lines[1]
    assert_equal '2:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[2]
    assert_equal '3:Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', lines[3]
  end

  def test_swapid
    @sock.gets

    # Test args = 0
    @sock.puts 'swapid'
    assert_equal "ACK [2@0] {swapid} wrong number of arguments for \"swapid\"\n", @sock.gets

    # Test args > 2
    @sock.puts 'swapid 1 2 3'
    assert_equal "ACK [2@0] {swapid} wrong number of arguments for \"swapid\"\n", @sock.gets

    # Test args not int
    @sock.puts 'swapid a 3'
    assert_equal "ACK [2@0] {swapid} \"a\" is not a integer\n", @sock.gets

    @sock.puts 'swapid 1 b'
    assert_equal "ACK [2@0] {swapid} \"b\" is not a integer\n", @sock.gets

    @sock.puts 'load Astral_Projection_-_Dancing_Galaxy'
    assert_equal "OK\n", @sock.gets

    # Test args out of bounds
    @sock.puts 'swapid 9999 7'
    assert_equal "ACK [50@0] {swapid} song id doesn't exist: \"9999\"\n", @sock.gets

    @sock.puts 'swapid 7 9999'
    assert_equal "ACK [50@0] {swapid} song id doesn't exist: \"9999\"\n", @sock.gets

    @sock.puts 'swapid -1 7'
    assert_equal "ACK [50@0] {swapid} song id doesn't exist: \"-1\"\n", @sock.gets

    @sock.puts 'swapid 7 -4'
    assert_equal "ACK [50@0] {swapid} song id doesn't exist: \"-4\"\n", @sock.gets

    @sock.puts 'swapid 8 12'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.size
    assert_equal '0:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[0]
    assert_equal '1:Astral_Projection/Dancing_Galaxy/6.Life_On_Mars.ogg', lines[1]
    assert_equal '2:Astral_Projection/Dancing_Galaxy/3.Flying_Into_A_Star.ogg', lines[2]
    assert_equal '3:Astral_Projection/Dancing_Galaxy/4.No_One_Ever_Dreams.ogg', lines[3]
    assert_equal '4:Astral_Projection/Dancing_Galaxy/5.Cosmic_Ascension_(ft._DJ_Jorg).ogg', lines[4]
    assert_equal '5:Astral_Projection/Dancing_Galaxy/2.Soundform.ogg', lines[5]
    assert_equal '6:Astral_Projection/Dancing_Galaxy/7.Liquid_Sun.ogg', lines[6]
    assert_equal '7:Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', lines[7]

    @sock.puts 'swapid 14 10'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.size
    assert_equal '0:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[0]
    assert_equal '1:Astral_Projection/Dancing_Galaxy/6.Life_On_Mars.ogg', lines[1]
    assert_equal '2:Astral_Projection/Dancing_Galaxy/3.Flying_Into_A_Star.ogg', lines[2]
    assert_equal '3:Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', lines[3]     
    assert_equal '4:Astral_Projection/Dancing_Galaxy/5.Cosmic_Ascension_(ft._DJ_Jorg).ogg', lines[4]
    assert_equal '5:Astral_Projection/Dancing_Galaxy/2.Soundform.ogg', lines[5]
    assert_equal '6:Astral_Projection/Dancing_Galaxy/7.Liquid_Sun.ogg', lines[6]
    assert_equal '7:Astral_Projection/Dancing_Galaxy/4.No_One_Ever_Dreams.ogg', lines[7]

    @sock.puts 'swapid 7 9'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'playlist'
    reply = get_response
    lines = reply.split "\n"
    assert_equal 8, lines.size
    assert_equal '0:Astral_Projection/Dancing_Galaxy/3.Flying_Into_A_Star.ogg', lines[0]
    assert_equal '1:Astral_Projection/Dancing_Galaxy/6.Life_On_Mars.ogg', lines[1]
    assert_equal '2:Astral_Projection/Dancing_Galaxy/1.Dancing_Galaxy.ogg', lines[2]
    assert_equal '3:Astral_Projection/Dancing_Galaxy/8.Ambient_Galaxy_(Disco_Valley_Mix).ogg', lines[3]
  end

  def test_update
    @sock.gets

    @sock.puts 'update 1 2'
    assert_equal "ACK [2@0] {update} wrong number of arguments for \"update\"\n", @sock.gets

    @sock.puts 'update a'
    assert_equal "updating_db: 1\n", @sock.gets
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 8, status.size
    assert_equal '1', status['updating_db']

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 7, status.size
    assert_nil status['updating_db']

    @sock.puts 'update'
    assert_equal "updating_db: 1\n", @sock.gets
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 8, status.size
    assert_equal '1', status['updating_db']

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal 7, status.size
    assert_nil status['updating_db']
  end

  def test_volume
    @sock.gets

    @sock.puts 'volume'
    assert_equal "ACK [2@0] {volume} wrong number of arguments for \"volume\"\n", @sock.gets

    @sock.puts 'volume 1 2'
    assert_equal "ACK [2@0] {volume} wrong number of arguments for \"volume\"\n", @sock.gets

    @sock.puts 'volume 30'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '30', status['volume']

    @sock.puts 'volume 10'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '40', status['volume']

    @sock.puts 'volume -15'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '25', status['volume']

    @sock.puts 'volume 0'
    assert_equal "OK\n", @sock.gets

    @sock.puts 'status'
    status = build_hash get_response
    assert_equal '25', status['volume']
  end
end
