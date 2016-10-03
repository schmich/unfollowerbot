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

  def self.followers(channel)
    names = Set.new

    last_request = Time.now

    follows_urls(channel) do |url|
      # Sleep 1 second between requests.
      now = Time.now
      delta = now - last_request
      delay = [1 - delta, 0].max
      sleep delay

      headers = {
        'Accept' => 'application/vnd.twitchtv.v3+json',
        'Client-ID' => self.client_id
      }

      json = JSON.parse(open(url, headers).read)
      last_request = now

      batch = json['follows'].map { |f| f['user']['name'] }
      break if batch.empty?
      names += batch
    end

    names.to_a
  end

  def self.follows_urls(channel)
    offset = 0
    loop do
      yield "https://api.twitch.tv/kraken/channels/#{channel}/follows?limit=100&offset=#{offset}&direction=ASC"
      offset += 80
    end
  end
end

class Diff
  def initialize(before, after)
    @before = before.dup
    @after = after.dup

    all_names = Set.new(@before + @after)
    original_names = Hash[all_names.map(&:downcase).zip(all_names)]

    @before.map!(&:downcase)
    @after.map!(&:downcase)

    @removed = before - after
    @added = after - before

    @removed.map! { |name| original_names[name] }
    @added.map! { |name| original_names[name] }
  end

  def removed
    @removed
  end

  def added
    @added
  end
end

class Snapshot
  def Snapshot.create(channel)
    $log.info "Creating snapshot for #{channel}."
    followers = Twitch.followers(channel)
    Snapshot.new(channel, followers)
  end

  def Snapshot.load(filename)
    File.open(filename, 'r') do |f|
      obj = JSON.parse(f.read)
      timestamp = Time.parse(obj['timestamp'])
      return Snapshot.new(obj['channel'], obj['followers'], timestamp)
    end
  end

  def save(filename)
    File.open(filename, 'w') do |f|
      snapshot = {
        channel: @channel,
        timestamp: @timestamp,
        followers: @followers
      }
      f.write JSON.dump(snapshot)
    end
  end

  attr_accessor :channel, :followers, :timestamp

  private

  def initialize(channel, followers, timestamp = Time.now.utc)
    @channel = channel
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

  def update(channel)
    FileUtils.mkdir_p(@snapshot_dir)
    snapshot_filename = "#{@snapshot_dir}/#{channel.downcase}.json"

    begin
      $log.info 'Loading previous snapshot.'
      before = Snapshot.load(snapshot_filename)
    rescue Errno::ENOENT
      $log.info 'Previous snapshot not found.'
    end

    after = Snapshot.create(channel)

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

      $log.info "Sending report to #{emails.join(', ')} for #{channel}."
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

channel = config[:twitch][:channel]
if !channel
  $log.error 'Channel is required.'
  exit 1
end

client_id = config[:twitch][:client_id]
if !client_id
  $log.error 'Client ID is required.'
  exit 1
end

Twitch.client_id = client_id

$log.info "Doing snapshot update for #{channel}."
snapshot_dir = File.absolute_path(File.join(File.dirname(__FILE__), 'snapshots'))
manager = SnapshotReportManager.new(config, snapshot_dir)
manager.update(channel)
$log.info 'Fin.'
