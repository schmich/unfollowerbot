require 'open-uri'
require 'json'
require 'mongo'
require 'set'
require 'mail'
require 'erb'
require 'tzinfo'

class Twitch
  def self.followers(username)
    names = Set.new

    follows_urls(username) do |url|
      json = JSON.parse(open(url, 'Accept' => 'application/vnd.twitchtv.v3+json').read)
      batch = json['follows'].map { |f| f['user']['name'] }
      break if batch.empty?
      names += batch
    end

    names.to_a
  end

  def self.follows_urls(username)
    offset = 0
    loop do
      yield "https://api.twitch.tv/kraken/channels/#{username}/follows?limit=100&offset=#{offset}&direction=ASC"
      offset += 90
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
  def initialize(collection)
    @collection = collection
  end

  def save(username)
    followers = Twitch.followers(username)

    snapshot = {
      channel: username,
      timestamp: Time.now.utc,
      followers: followers
    }

    @collection.insert(snapshot)
  end

  def recent_snapshots(username)
    docs = @collection.find({ channel: /^#{username}$/i }).sort({ timestamp: -1 }).limit(2).to_a
    after, before = docs
    after ||= []
    before ||= []
    [before, after]
  end
end

class Report
  def initialize(before, after)
    before_followers = before['followers']
    after_followers = after['followers']

    @before = before
    @after = after
    @diff = Diff.new(before_followers, after_followers)
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

  def html
    template_path = File.absolute_path(File.join(File.dirname(__FILE__), 'report.html.erb'))
    template = ERB.new(File.read(template_path))
    return template.result(binding)
  end
end

def mail_report(email, snapshot_before, snapshot_after)
  Mail.defaults do
    delivery_method :smtp, {
      address: 'smtp.gmail.com',
      port: 587,
      user_name: 'unfollowerbot@gmail.com',
      password: ENV['UNFOLLOWERBOT_EMAIL_PASSWORD'],
      authentication: 'plain',
      enable_starttls_auto: true
    }
  end

  Mail.deliver do
    to email
    from 'unfollowerbot <unfollowerbot@gmail.com>'
    subject "Twitch follower report for #{Time.now.strftime('%m/%d')}"

    html_part do
      content_type 'text/html; charset=UTF-8'
      body Report.new(snapshot_before, snapshot_after).html
    end
  end
end

def send_report(username, email)
  mongo = Mongo::MongoClient.new('127.0.0.1')
  db = mongo.db('unfollowerbot')
  collection = db.collection('snapshots')

  snapshot = Snapshot.new(collection)
  snapshot.save(username)

  before, after = snapshot.recent_snapshots(username)
  mail_report(email, before, after)
end

username = ARGV[0]
email = ARGV[1]

if !username || !email
  puts 'Usage: snapshot <twitch username> <email>'
  exit -1
end

send_report(username, email)
