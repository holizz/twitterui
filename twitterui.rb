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
    config_file = ENV['HOME'] + '/' + '.twitteruirc'
    config = load_config(config_file)

    @login = config[:user] || nil
    @password = config[:password] || nil
    @twitter = Twitter::Base.new @login, @password
    @coder = HTMLEntities.new
  end

  def load_config(file)
    config = {}
    if File.exists? file
      File.open(file) do |fd|
        config = YAML::load(fd)
      end
    end
    config
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

  # update status on Twitter
  def update_status
    @twitter.post @up_text.text
    @up_text.text = ''
  end

  # format twitter status message into eval-able code
  def format_status(status)
    user = status.user.screen_name
    "[ em(
        link(\"#{user}\", :click => \"http://twitter.com/#{user}\",
             :underline => false,
             :stroke => \"#bfd34a\",
             :fill => gray(0.1)) ,
             :size => 7 ),
       em(\": \", :size => 7, :stroke => white),
      "+format_links(status.text)+"
    ]"
  end

  # format links out of a twitter status message
  def format_links(text)
    return '"'+text+'"' unless text.include? 'http'

    text.split.collect do |tok|
      if tok =~ /http:\/\//
        tok.gsub(/http:\/\/.*/, 'link("\0", :click => "\0",' +
                                ':stroke => orange, :fill => gray(0.1))') + ' '
      else
        "\"#{tok} \""
      end
    end.join(',')
  end

  # shows update edit-box & refresh links...
  def control_box
    @shown = false   # @up_stack.toggle fails ¬¬
    flow :width => -20, :margin => 10 do
      background gray(0.1), :radius => 10

      # Status' edit-box
      @up_stack = stack :width => 1.0, :margin => 8, :hidden => true do
        @up_text = edit_box "What are you doing?", :width => 1.0, :height => 50
        para link('post!', :size => 8, :stroke => "#bfd34a", :font => "Verdana", :fill => gray(0.1)) {
          update_status
        }, :align => "right"
      end

      # Edit-box toggle & refresh links
      stack :width => -60 do
        para link('update your status', :size => 8, :stroke => "#bfd34a", :fill => gray(0.1) ) {
          if @shown
            @up_stack.hide
            @shown = false
          else
            @up_stack.show
            @shown = true
          end
        }, " | ", link('refresh', :size => 8, :stroke => "#bfd34a", :fill => gray(0.1) ) {
          visit('/')
        }, :stroke => white, :font => "Verdana", :size => 8
      end

      # Twitter IM bot logo goes here.
      stack :width => 40, :margin_bottom => 16 do
        image "twitter.png", :align => "top"
      end
    end
  end

  def config(show_welcome = nil)
    background black
    background gray(0.1), :radius => 10
    
    if show_welcome
      stack :width => 1.0 do
        banner "Welcome...\n", :stroke => "#bfd34a", :size => 14
        para "to this tiny Shoes app!\n\n",
            "It seems you've never launched me, so we need to know each other better",
            " so I can get you to twitter.",
            :font => "Verdana", :size => 8, :stroke => white
      end
    end
    
    stack :width => 1.0 do
      para "Login: ", :font => "Verdana", :size => 8, :stroke => white
      login = edit_line
      para "Password: ", :font => "Verdana", :size => 8, :stroke => white
      password = edit_line
    end
    
  end

  # Go Shoes ! \o/
  def index
    puts "starting..."
    @twitter = TwitterApp.new
    puts "config missing" if @twitter.login.nil?
    visit('/config/with_welcome') if @twitter.login.nil?

    background black
    control_box
    @twitter.tweets.each do |status|
      stack :width => -20, :margin => 5 do
        background gray(0.1), :radius => 10
        flow :width => -5 do
          stack :width => 48, :margin => 5 do
            image status.user.profile_image_url   # FIXME cache please
          end
          stack :width => -48, :margin => 10 do
            eval "para " + format_status(status) +
                  ", :font => \"Verdana\", :size => 8, :stroke => white"
          end
        end
      end
    end
  end

end

Shoes.app :title => 'Twitter UI', :width => 300, :height => 350
