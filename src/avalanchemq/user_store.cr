require "json"
require "./user"

module AvalancheMQ
  class UserStore
    include Enumerable(User)

    def initialize(@data_dir : String, @log : Logger)
      @users = Hash(String, User).new
      load!
    end

    def each
      @users.values.each { |e| yield e }
    end

    def [](name)
      @users[name]
    end

    def []?(name)
      @users[name]?
    end

    def size
      @users.size
    end

    # Adds a user to the use store
    # Returns nil if user is already created
    def create(name, password, tags = Array(Tag).new, save = true)
      return if @users.has_key?(name)
      user = User.create(name, password, "Bcrypt", tags)
      @users[name] = user
      save! if save
      user
    end

    def add(name, password_hash, password_algorithm, tags = Array(Tag).new, save = true)
      return if @users.has_key?(name)
      user = User.new(name, password_hash, password_algorithm, tags)
      @users[name] = user
      save! if save
      user
    end

    def add_permission(user, vhost, config, read, write)
      perm = { config: config, read: read, write: write }
      @users[user].permissions[vhost] = perm
      @users[user].invalidate_acl_caches
      save!
      perm
    end

    def rm_permission(user, vhost)
      if perm = @users[user].permissions.delete vhost
        @users[user].invalidate_acl_caches
        save!
        perm
      end
    end

    def delete(name, save = true) : User?
      if user = @users.delete name
        save! if save
        user
      end
    end

    def to_json(json : JSON::Builder)
      @users.values.to_json(json)
    end

    private def load!
      path = File.join(@data_dir, "users.json")
      if File.exists? path
        @log.debug "Loading users from file"
        File.open(path) do |f|
          Array(User).from_json(f) do |user|
            @users[user.name] = user
          end
        end
      else
        tags = [Tag::Administrator]
        @log.debug "Loading default users"
        create("guest", "guest", tags, save: false)
        add_permission("guest", "/", /.*/, /.*/, /.*/)
        create("bunny_gem", "bunny_password", tags, save: false)
        add_permission("bunny_gem", "bunny_testbed", /.*/, /.*/, /.*/)
        create("bunny_reader", "reader_password", tags, save: false)
        add_permission("bunny_reader", "bunny_testbed", /.*/, /.*/, /.*/)
        save!
      end
      @log.debug("#{@users.size} users loaded")
    end

    def save!
      @log.debug "Saving users to file"
      tmpfile = File.join(@data_dir, "users.json.tmp")
      File.open(tmpfile, "w") { |f| self.to_json(f) }
      File.rename tmpfile, File.join(@data_dir, "users.json")
    end
  end
end
