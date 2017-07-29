require 'open-uri'
require 'json'
require 'set'
require 'mail'
require 'erb'
require 'tzinfo'
require 'logger'
require 'fileutils'

class Twitch
  class << self
    attr_accessor :client_id
  end

  def self.followers(channel_id)
    names = Set.new

    last_request = Time.now

    cursor = nil
    loop do
      # Sleep 1 second between requests.
      now = Time.now
      delta = now - last_request
      delay = [1 - delta, 0].max
      sleep delay

      headers = {
        'Accept' => 'application/vnd.twitchtv.v5+json',
        'Client-ID' => self.client_id
      }

      url = follows_url(channel_id, cursor)
      json = JSON.parse(open(url, headers).read)
      last_request = now

      batch = json['follows'].map do |follower|
        {
          id: follower['user']['_id'],
          name: follower['user']['display_name']
        }
      end

      break if batch.empty?
      names += batch

      cursor = json['_cursor']
    end

    names.to_a
  end

  def self.follows_url(channel_id, cursor)
    if cursor
      "https://api.twitch.tv/kraken/channels/#{channel_id}/follows?limit=100&cursor=#{cursor}&direction=ASC"
    else
      "https://api.twitch.tv/kraken/channels/#{channel_id}/follows?limit=100&direction=ASC"
    end
  end
end

class Diff
  def initialize(before, after)
    before = Set.new(before.dup)
    after = Set.new(after.dup)

    names = Hash[(before + after).map { |f| [f[:id], f[:name]] }]

    before_ids = Set.new(before.map { |f| f[:id] })
    after_ids = Set.new(after.map { |f| f[:id] })

    removed = before_ids - after_ids
    added = after_ids - before_ids

    @removed = removed.map { |id| names[id] }
    @added = added.map { |id| names[id] }
  end

  def removed
    @removed
  end

  def added
    @added
  end
end

class Snapshot
  def Snapshot.create(channel_id)
    $log.info "Creating snapshot for #{channel_id}."
    followers = Twitch.followers(channel_id)
    Snapshot.new(channel_id, followers)
  end

  def Snapshot.load(filename)
    File.open(filename, 'r') do |f|
      obj = JSON.parse(f.read, symbolize_names: true)
      timestamp = Time.parse(obj[:timestamp])
      return Snapshot.new(obj[:channel_id], obj[:followers], timestamp)
    end
  end

  def save(filename)
    File.open(filename, 'w') do |f|
      snapshot = {
        channel_id: @channel_id,
        timestamp: @timestamp,
        followers: @followers
      }
      f.write JSON.dump(snapshot)
    end
  end

  attr_accessor :channel_id, :followers, :timestamp

  private

  def initialize(channel_id, followers, timestamp = Time.now.utc)
    @channel_id = channel_id
    @followers = followers
    @timestamp = timestamp
  end
end

class Report
  def initialize(before, after)
    @before = before
    @after = after
    @diff = Diff.new(before.followers, after.followers)
  end

  def before
    @before
  end

  def after
    @after
  end

  def removed
    @diff.removed
  end

  def added
    @diff.added
  end

  def email(emails, email_configuration)
    Mail.defaults do
      delivery_method :smtp, email_configuration
    end

    address = email_configuration[:user_name]

    body = to_html
    Mail.deliver do
      to emails
      from "Unfollowerbot <#{address}>"
      subject "Twitch follower report for #{Time.now.strftime('%b %d')}"

      html_part do
        content_type 'text/html; charset=UTF-8'
        body body
      end
    end
  end

  private

  def to_html
    template_path = File.absolute_path(File.join(File.dirname(__FILE__), 'report.html.erb'))
    template = ERB.new(File.read(template_path))
    return template.result(binding)
  end
end

class SnapshotReportManager
  def initialize(config, snapshot_dir)
    @config = config
    @snapshot_dir = snapshot_dir
  end

  def update(channel_id)
    FileUtils.mkdir_p(@snapshot_dir)
    snapshot_filename = "#{@snapshot_dir}/#{channel_id}.json"

    begin
      $log.info 'Loading previous snapshot.'
      before = Snapshot.load(snapshot_filename)
    rescue Errno::ENOENT
      $log.info 'Previous snapshot not found.'
    end

    after = Snapshot.create(channel_id)

    begin
      if !before || !after
        $log.info 'No snapshot to compare with, not sending report.'
        return
      end

      report = Report.new(before, after)
      if report.removed.empty? && report.added.empty?
        $log.info 'No new followers or unfollowers, not sending report.'
        return
      end

      emails = @config[:email][:to]
      if !emails || emails.empty?
        $log.info 'No email recipients, not sending report.'
        return
      end

      $log.info "Sending report to #{emails.join(', ')} for #{channel_id}."
      report.email(emails, @config[:email])
    ensure
      after.save(snapshot_filename)
    end
  end
end

$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

config_file = ARGV[0]
if !config_file
  $log.error 'Usage: snapshot <config file>'
  exit 1
end

config = JSON.parse(File.read(config_file), symbolize_names: true)

channel_id = config[:twitch][:channel_id]
if !channel_id
  $log.error 'Channel ID is required.'
  exit 1
end

client_id = config[:twitch][:client_id]
if !client_id
  $log.error 'Client ID is required.'
  exit 1
end

Twitch.client_id = client_id

$log.info "Doing snapshot update for #{channel_id}."
snapshot_dir = File.absolute_path(File.join(File.dirname(__FILE__), 'snapshots'))
manager = SnapshotReportManager.new(config, snapshot_dir)
manager.update(channel_id)
$log.info 'Fin.'
