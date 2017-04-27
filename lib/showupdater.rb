require_relative 'tvdb'
require 'nokogiri'

class ShowUpdater
  def initialize(show)
    @show = show
  end

  def update
    puts "going to update show ##{@show.id} (#{@show.title})"

    # If no tvdbid is set, we cannot update so we return
    return unless @show.tvdbid

    # Download content
    parsedXml = Nokogiri::XML(TVDB.getShowXML(@show.tvdbid))
    show = parsedXml.xpath('/Data/Series')
    episodes = parsedXml.xpath('/Data/Episode')

    # If we don't have a title and the remote XML has no title either, return
    # @TODO test on content without title
    if @show.title && show.at_xpath('SeriesName').content.length == 0
      return
    end

    @show.title = show.at_xpath('SeriesName').content
    @show.status = show.at_xpath('Status').content
    @show.description = show.at_xpath('Overview').content
    @show.language = show.at_xpath('Language').content
    @show.airsdayofweek = show.at_xpath('Airs_DayOfWeek').content
    @show.airstime = show.at_xpath('Airs_Time').content
    @show.contentrating = show.at_xpath('ContentRating').content
    @show.runtime = show.at_xpath('Runtime').content

    @show.firstaired = nil
    if show.at_xpath('FirstAired').content.length > 0
      @show.firstaired = DateTime.parse(show.at_xpath('FirstAired').content)
    end

    @show.imdb_id = show.at_xpath('IMDB_ID').content
    @show.invisible = 0

    @show.edited = DateTime.now

    @show.save

    # Set network
    network = SDNetwork.find(:title => show.at_xpath('Network').content)
    if !network
      network = SDNetwork.create(
        :title => show.at_xpath('Network').content
      ).save
    end
    @show.network = network

    # Fix genres
    @show.remove_all_genres
    parse_genres(show.at_xpath('Genre').content).each { |g|
      genre = SDGenre.find(:title => g)
      if !genre
        genre = SDGenre.create(
          :title => g
        ).save
      end

      @show.add_genre(genre)
    }

    currentSeasonId = nil
    currentSeason = nil

    # Unlink all episodes and seasons
    @show.remove_all_episodes
    @show.remove_all_seasons

    # Fix episodes/seasons
    episodes.each { |episode|
      next if episode.at_xpath('EpisodeName').content.empty?

      # Figure out the season
      if currentSeasonId != episode.at_xpath('seasonid').content
        currentSeason = SDSeason.find(:tvdbid => episode.at_xpath('seasonid').content)

        if !currentSeason
          currentSeason = SDSeason.create(
            :tvdbid => episode.at_xpath('seasonid').content
          )
        end

        currentSeason.title = episode.at_xpath('SeasonNumber').content
        currentSeason.order = episode.at_xpath('SeasonNumber').content
        currentSeason.show = @show
        currentSeason.save
      end

      ep = SDEpisode.find(:tvdbid => episode.at_xpath('id').content)
      if !ep
        ep = SDEpisode.create(
          :tvdbid => episode.at_xpath('id').content,
          :created => DateTime.now
        )
      end

      ep.season = currentSeason
      ep.show = @show
      ep.title = episode.at_xpath('EpisodeName').content
      ep.description = episode.at_xpath('Overview').content
      ep.language = episode.at_xpath('Language').content
      ep.imdb_id = episode.at_xpath('IMDB_ID').content

      ep.airsbefore_season = nil
      if episode.at_xpath('airsbefore_season')
        ep.airsbefore_season = episode.at_xpath('airsbefore_season').content
      end

      ep.airsbefore_episode = nil
      if episode.at_xpath('airsbefore_episode')
        ep.airsbefore_episode = episode.at_xpath('airsbefore_episode').content
      end

      ep.order = episode.at_xpath('EpisodeNumber').content

      ep.firstaired = nil
      if episode.at_xpath('FirstAired').content.length > 0
        ep.firstaired = DateTime.parse(episode.at_xpath('FirstAired').content)
      end

      ep.edited = DateTime.now

      ep.save
    }

    puts "...done"
  end

  private

  def parse_genres(genre_string)
    genre_string.split('|').reject { |c| c.empty? }
  end
end