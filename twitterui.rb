#!/usr/bin/ruby

Shoes.setup do
  gem 'htmlentities'
  gem 'twitter'
end

require 'htmlentities'
require 'twitter'
require 'yaml'

# ----------------------------------------------------------------- [ twitter ]

class TwitterApp
  attr :login
  attr :password
  attr :twitter

  def initialize
    @config_file = ENV['HOME'] + '/' + '.twitteruirc'
    config = load_config
    connect(config)
  end

  def load_config
    config = nil
    if File.exists? @config_file
      File.open(@config_file) do |fd|
        config = YAML::load(fd)
      end
    end
    config
  end

  def save_config(opts)
    File.open(@config_file, File::WRONLY|File::TRUNC|File::CREAT, 0600) do |fd|
      fd.puts YAML::dump(opts)
    end
    connect(opts)
  end

  def connect(config = nil)
    unless config.nil?
      @login    = config[:user]
      @password = config[:password]
      @twitter  = Twitter::Base.new @login, @password
      @coder    = HTMLEntities.new
    end
  end

  # get friends timeline & decode XML entities out of twitter.
  def tweets
    @twitter_timeline = @twitter.timeline :friends
    return [] if @twitter_timeline.nil?

    @twitter_timeline.each do |s|
      s.text = @coder.decode(s.text)
    end
  end

  # update your twitter status
  def post(msg)
    @twitter.post msg
  end
  alias update post
end

# ------------------------------------------------------------------- [ shoes ]

class TwitterUI < Shoes
  url '/', :index
  url '/config/(\w+)', :config

  # Keep the app's context & status under there.
  @@context = {
    :twitter     => nil,
    :tweets_flow => nil,
    :sleeptime   => 120
  }

  # Config Page
  def config(show_welcome = nil)
    background gray(0.1)
 
    if show_welcome
      stack :width => 1.0 do
        banner "Welcome...\n", :stroke => "#bfd34a", :size => 14
        para "to this tiny Shoes app!\n\n",
            "It seems you've never launched me, so we need to know each other better",
            " so I can get you to twitter.",
            :font => "Verdana", :size => 8, :stroke => white
      end
    end
 
    stack :margin_top => 5 do
      para "Login: \n", :font => "Verdana", :size => 8, :stroke => white, :margin_left => 20
      @login = edit_line :margin_left => 20
    end
    stack :margin_top => 5 do
      para "Password: \n", :font => "Verdana", :size => 8, :stroke => white, :margin_left => 20
      @password = edit_line :margin_left => 20, :secret => true
    end

    button "Connect !", :margin_left => 20 do
      if @login.text != "" && @password.text != ""
        @@context[:twitter].save_config(:user => @login.text, :password => @password.text)
        visit('/')
      else
        alert "*cough* I really need a login and password please. ^^"
      end
    end

    button "No, thanks.", :margin_left => 5 do
      quit
    end
  end

  # Go Shoes ! \o/
  def index
    @@context[:twitter] = TwitterApp.new if @@context[:twitter].nil?
    visit '/config/with_welcome' if @@context[:twitter].login.nil?
    background black
    display_control_box
    load_tweets 'Loading...'
    wait_for_tweets
  end

  # Bye Shoes !
  def quit
    current = Thread.current
    Thread.list.each { |t| t.join unless t == current }
    exit
  end

  protected

  # format twitter status message into eval-able code
  def format_status(status, bg)
    user = status.user.screen_name
    "[ em(
        link(\"#{user}\", :click => \"http://twitter.com/#{user}\",
             :underline => false,
             :stroke => \"#bfd34a\",
             :fill => \"#{bg}\") ,
             :size => 7 ),
       em(\": \", :size => 7, :stroke => white),
      " + format_text(status.text, bg) + ", 
      em(\" (" + rel_time(status.created_at) + ") \", :size => 7, :stroke => white)
    ]"
  end

  # format text and links out of a twitter status message
  def format_text(text, bg)
    text.gsub!(/\\/, "\\\\\\")
    text.gsub!(/"/, '\"')
    return '"'+text+'"' unless text.include? 'http'

    # Clickable links.
    text.split.collect do |tok|
      if tok =~ /http:\/\//
        tok.gsub(/(.*)(http:\/\/.*)/, '"\1", link("\2", :click => "\2",' +
                                ':stroke => orange, :fill => "'+bg+'"), " "') + ' '
      else
        "\"#{tok} \""
      end
    end.join(', ')
  end

  # shows update edit-box & refresh links...
  def display_control_box
    @shown = false   # @status_flow.toggle fails ¬¬
    char_left = 140
    char_text = "%d character%s left."

    flow :width => -20, :margin => 10 do
      background gray(0.1), :radius => 10

      # Edit-box toggle & refresh links
      image "media/new_post.png", :margin => 2 do
        if @shown
          @status_flow.hide
          @shown = false
        else
          @status_flow.show
          @shown = true
        end
      end
      image "media/refresh.png", :margin => 2 do
        load_tweets 'Refreshing...'
      end

      # Twitter logo
      image "media/twitter_logo.png", :left => "83%", :margin => 2,
            :click => "http://twitter.com"

      # Status' edit-box
      @status_flow = flow :width => 1.0, :margin => 8, :hidden => true do

        # Edit-box input
        @up_text = edit_box "What are you doing?", :width => 1.0, :height => 50 do
          char_left = 140 - @up_text.text.size
          char_left = 0 if char_left < 0
          text = char_text % [char_left, (char_left > 1) ? 's' : '']
          @char_count.replace text
        end

        stack :width => -20 do
          # Characters left para
          text = char_text % [char_left, (char_left > 1) ? 's' : '']
          @char_count = para text, :stroke => white, :font => "Verdana", :size => 8
        end

        # Save button
        image "media/save.png", :margin => 2 do
          update_status
        end
      end
    end
  end

  # Show twitter satuses
  def display_tweets(tweets)
    @@context[:tweets_flow].clear unless @@context[:tweets_flow].nil?
    @@context[:tweets_flow] = flow :margin => 0, :width => 1.0 do
      tweets.each do |status|
        stack :width => -20, :margin => 5 do
          bg_color = ( status.user.screen_name != @@context[:twitter].login ) ? "#191919" : "#39414A"
          background bg_color, :radius => 10

          flow :width => -5 do
            stack :width => 48, :margin => 5 do
              image status.user.profile_image_url   # FIXME cache please
            end
            stack :width => -48, :margin => 10 do
              eval "para " + format_status(status, bg_color) +
                    ", :font => \"Verdana\", :size => 8, :stroke => white"
            end
          end
        end
      end
    end
  end

  # Display a loading message, and reset the loading timer
  def load_tweets(msg = "Refresing...")
    @status_msg = status_msg(msg)
    @@context[:seconds_to_reload] = 0
  end

  # Load and displays tweets in their own thread.
  def wait_for_tweets
    tweets = nil
    last_check = nil
    Thread.new do
      while true do
        tweets = @@context[:twitter].tweets
        @@context[:seconds_to_reload] = @@context[:sleeptime]
        if last_check.nil? || tweets.first.created_at > last_check.created_at
          display_tweets(tweets)
        end
        last_check = tweets.first
        @status_msg.replace ""
        sleep 1 until 0 >= (@@context[:seconds_to_reload] -= 1)
      end
    end
  end

  # Displays a text status para on top of the app
  def status_msg(msg)
    if @status_msg
      @status_msg.replace msg
      return @status_msg
    end

    if @@context[:tweets_flow].nil?
      @status_msg = para msg, :stroke => white, :font => "Verdana", :size => 8
    else
      @@context[:tweets_flow].before do
        @status_msg = para msg, :stroke => white, :font => "Verdana", :size => 8
      end
    end
    @status_msg
  end

  # Update status on Twitter
  def update_status
    @status_msg = status_msg('Sending...')

    Thread.new do
      @@context[:twitter].post @up_text.text
      @status_msg.replace ""
    end
    @up_text.text = ""
  end

  # Relative date/time
  def rel_time(dt)
    dt =  Time.now - Time.parse(dt)
    case dt
      when 1..60
        "#{dt.to_i} secs ago"
      when 60..120
        "#{(dt/60).to_i} min ago"
      when 120..3600
        "#{(dt/60).to_i} mins ago"
      when 3600..7200
        "#{(dt/60/60).to_i} hour ago"
      when 7200..86400
        "#{(dt/60/60).to_i} hours ago"
      when 86400..172800
        "#{(dt/60/60).to_i} day ago"
      else
        "#{(dt/60/60/60).to_i} days ago"
    end
  end

end

Shoes.app :title => 'Twitter UI', :width => 300, :height => 350
