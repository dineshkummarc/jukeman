class Journal < ActiveRecord::Base
  class << self
    def record(command)
      Journal.create(:command => command)
    end

    # SONGS
    def add_song(url, uuid)
      Journal.record("Song.download(\"#{url}\", \"#{uuid}\")")
    end

    # PLAYLISTS
    def new_playlist(name)
      if @playlist = Playlist.create(:name => name)
        Journal.record("Playlist.create(\"#{name}\")")
        return @playlist
      else
        nil
      end
    end

    def rename_playlist(old_name, new_name)
      if Playlist.rename(old_name, new_name)
        Journal.record("Playlist.rename(\"#{old_name}\", \"#{new_name}\")")
      else
        nil
      end
    end

    def remove_playlist(playlist_name)
      if Playlist.remove(playlist_name)
        Journal.record("Playlist.remove(\"#{playlist_name}\")")
      else
        nil
      end
    end

    def add_song_to_playlist(playlist_name, song_uuid)
      if Playlist.add_song(playlist_name, song_uuid)
        Journal.record("Playlist.add_song(\"#{playlist_name}\", \"#{song_uuid}\")")
      else
        nil
      end
    end

    
  end

  def apply
    eval(command)
  end
end
