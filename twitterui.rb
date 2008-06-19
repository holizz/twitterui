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
  url '/config', :config
  url '/first_config', :first_config

  # Keep the app's context & status under there.
  @@context = {
    :twitter     => nil,
    :tweets_flow => nil,
    :sleeptime   => 120,      # Check timeline every 2 minutes
    :timeout     => 30        # Don't wait for Twitter more than 30 seconds
  }

  # First time config page: ask for login & password
  def first_config
    background gray(0.1)
    stack :width => 1.0 do
      banner "Welcome...\n", :stroke => "#bfd34a", :size => 14
      para "to this tiny Shoes app!\n\n",
          "It seems you've never launched me, so we need to know each other better",
          " so I can get you to twitter.",
          :font => "Verdana", :size => 8, :stroke => white
    end
 
    stack :margin_top => 5 do
      para "Login: \n", :font => "Verdana", :size => 8, :stroke => white, :margin_left => 20
      @login = edit_line :margin_left => 20, :width => '200px'
    end
    stack :margin_top => 5 do
      para "Password: \n", :font => "Verdana", :size => 8, :stroke => white, :margin_left => 20
      @password = edit_line :margin_left => 20, :secret => true, :width => '200px'
    end

    button "No, thanks.", :margin_left => 5 do
      quit
    end
    button "Ok, connect !", :margin_left => 20 do
      if @login.text != "" && @password.text != ""
        @@context[:twitter].save_config(:user => @login.text, :password => @password.text)
        visit('/')
      elsif 1 == show_welcome
        alert "*cough* I really need a login and password please. ^^"
      end
    end
  end

  # "Main" config page.
  def config
    @@context[:busy] = true
    background gray(0.1)
    login = @@context[:twitter].login ? @@context[:twitter].login : 'username?'
    stack :width => 1.0 do
      banner "Configure...\n", :stroke => "#bfd34a", :size => 14
      para "Configure TwitterUI: you can only change your twitter credentials, for now.", 
          :font => "Verdana", :size => 8, :stroke => white
    end
    stack :margin_bottom => 15 do
      para "Login:", :font => "Verdana", :size => 8, :stroke => white, :margin_left => 20
      @login = edit_line login, :margin_left => 20, :width => '200px'
    end
    stack :margin_bottom => 25 do
      para "Password:", :font => "Verdana", :size => 8, :stroke => white, :margin_left => 20
      @password = edit_line '', :margin_left => 20, :secret => true, :width => '200px'
    end

    button "Cancel", :margin_left => 5 do
      visit('/')
    end
    button "Save", :margin_left => 20 do
      if @login.text != "" && @password.text != ""
        @@context[:twitter].save_config(:user => @login.text, :password => @password.text)
        visit('/')
      end
    end
  end

  # Go Shoes ! \o/
  def index
    background black
    display_control_box
    @@context[:busy] = nil
    @@context[:tweets_flow] = nil

    if @@context[:twitter].nil?
      @@context[:twitter] = TwitterApp.new 
      visit '/first_config' if @@context[:twitter].login.nil?
      load_tweets 'Loading...'
      wait_for_tweets

      # Check (in a rather clumsy way) that we're not waiting
      # Twitter too long.
      Thread.new do
        while true do
          timeouted = (Time.now - @@context[:twitter_check]) > @@context[:timeout]
          if @@context[:twitter_check] != nil && timeouted && !@@context[:busy]
            @@context[:twitter_thread].terminate
            @@context[:twitter_thread] = nil
            load_tweets 'Loading...'
            wait_for_tweets
          end
          sleep 5
        end
      end
    else
      load_tweets 'Loading...'
    end

    # Keyboard shortcuts.
    keypress do |key|
      case key.to_s
        when "f5"   then load_tweets
        when "\022" then load_tweets
        when "\e":
          @status_flow.hide
        when "\016":
          @status_flow.show
        when "\021" then quit
      end
    end
  end

  # Bye Shoes !
  def quit
    current = Thread.current
    main    = Thread.main
    Thread.list.each { |t| t.kill unless t == current || t == main }
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
    text.gsub!(/&lt;/, '<')
    text.gsub!(/&gt;/, '>')
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
    char_left = 140
    char_text = "%d character%s left."

    flow :width => -20, :margin => 10 do
      background gray(0.1), :curve => 10

      # Edit-box toggle & refresh links
      image "media/new_post.png", :margin => 2 do
        @status_flow.toggle
      end
      image "media/refresh.png", :margin => 2 do
        load_tweets 'Refreshing...'
      end
      image "media/config.png", :margin => 2 do
        visit '/config'
      end

      # Twitter logo
      image "media/twitter_logo.png", :left => "83%", :margin => 2,
            :click => "http://twitter.com"

      # Status' edit-box
      @status_flow = flow :width => 1.0, :margin => 8, :hidden => true do

        # Edit-box input
        @up_text = edit_box "What are you doing?", :width => 1.0, :height => 50 do
          char_left = 140 - @up_text.text.size
          text = char_text % [char_left, (char_left != 1) ? 's' : '']
          @char_count.replace text
        end

        stack :width => -20 do
          # Characters left para
          text = char_text % [char_left, (char_left != 1) ? 's' : '']
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
          background bg_color, :curve => 10

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
    last_tweets = nil

    Thread.new do
      @@context[:twitter_thread] = Thread.current
      while true do

        # Don't load anything if the app is busy in config mode or whatever.
        # (I wish shoes supported multiple windows ^^;)
        unless @@context[:busy]
          # Ask Twitter.
          @@context[:twitter_check] = Time.now
          tweets = @@context[:twitter].tweets
          @@context[:twitter_check] = nil
        end

        # Display timeline if needed, then wait until it's time to reload
        # again...
        @@context[:seconds_to_reload] = @@context[:sleeptime]
        if last_tweets.nil? || tweets.zip(last_tweets).any? {|t,l|t.created_at!=l.created_at}
          display_tweets(tweets)
        end
        last_tweets = tweets
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
      load_tweets
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
