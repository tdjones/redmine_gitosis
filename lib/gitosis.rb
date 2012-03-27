require 'lockfile'
require 'inifile'
require 'net/ssh'

module Gitosis
  #initialize the directory location of gitosis-admin repository
  @local_dir = File.join(RAILS_ROOT,"tmp","gitosis_admin")

	def self.renderUrls(baseUrlStr, projectId, isReadOnly)
		rendered = ""
		if(baseUrlStr.length == 0)
			return rendered
		end
		baseUrlList=baseUrlStr.split(/[\r\n\t ,;]+/)

		if(not defined?(baseUrlList.length))
			return rendered
		end


		rendered = rendered + "<strong>" + (isReadOnly ? "Read Only" : "Developer") + " " + (baseUrlList.length == 1 ? "URL" : "URLs") + ": </strong><br/>"
				rendered = rendered + "<ul>";
				for baseUrl in baseUrlList do
						rendered = rendered + "<li>" + "<span style=\"width: 95%; font-size:10px\">" + baseUrl + projectId + ".git</span></li>"
				end
		rendered = rendered + "</ul>\n"
		return rendered
	end

	def self.update_repositories(projects)
		projects = (projects.is_a?(Array) ? projects : [projects])
    lockfile=File.new(File.join(RAILS_ROOT,"tmp",'redmine_gitosis_lock'),File::CREAT|File::RDONLY)
    retries=5
    loop do
      break if lockfile.flock(File::LOCK_EX|File::LOCK_NB)
      retries-=1
      sleep 2
      raise Lockfile::MaxTriesLockError if retries<=0
    end
    self.initialize_gitosis_repository()

    `cd #{@local_dir} ; git pull`

    #track changes
		changes = Array.new
    projects.select{|p| p.repository.is_a?(Repository::Git)}.each do |project|
			# fetch users
			users = project.member_principals.map(&:user).compact.uniq
			write_users = users.select{ |user| user.allowed_to?( :commit_access, project ) }
			read_users = users.select{ |user| user.allowed_to?( :view_changesets, project ) && !user.allowed_to?( :commit_access, project ) }

			# write key files
			users.map{|u| u.gitosis_public_keys.active}.flatten.compact.uniq.each do |key|
        changes << "Added ssh keyfile #{key.identifier}.pub" unless File.exist?(File.join(@local_dir, 'keydir',"#{key.identifier}.pub"))
				File.open(File.join(@local_dir, 'keydir',"#{key.identifier}.pub"), 'w') {|f| f.write(key.key.gsub(/\n/,'')) }
			end

			# delete inactives
			users.map{|u| u.gitosis_public_keys.inactive}.flatten.compact.uniq.each do |key|
        changes << "Removed ssh keyfile #{key.identifier}.pub" unless !File.exist?(File.join(@local_dir, 'keydir',"#{key.identifier}.pub"))
				File.unlink(File.join(@local_dir, 'keydir',"#{key.identifier}.pub")) rescue nil
			end

			# write config file
			conf = IniFile.new(File.join(@local_dir,'gitosis.conf'))
			original = conf.clone
			name = "#{project.identifier}"

			conf["group #{name}_readonly"]['readonly'] = name
			conf["group #{name}_readonly"]['members'] = read_users.map{|u| u.gitosis_public_keys.active}.flatten.map{ |key| "#{key.identifier}" }.join(' ')

			conf["group #{name}"]['writable'] = name
			conf["group #{name}"]['members'] = write_users.map{|u| u.gitosis_public_keys.active}.flatten.map{ |key| "#{key.identifier}" }.join(' ')

      changes << "Added/Removed 'readonly' pubkey for project #{name}" unless original["group #{name}_readonly"]['members'] == conf["group #{name}_readonly"]['members']
      changes << "Added/Removed 'writable' pubkey for project #{name}" unless original["group #{name}"]['members'] == conf["group #{name}"]['members']

			# git-daemon support for read-only anonymous access
			if User.anonymous.allowed_to?( :view_changesets, project )
				conf["repo #{name}"]['daemon'] = 'yes'
			else
				conf["repo #{name}"]['daemon'] = 'no'
      end

      changes << "Changed anonymous access for #{name}" unless conf["repo #{name}"]['daemon'] == original["repo #{name}"]['daemon']

      if changes.empty? && !conf.eql?(original)
        Rails.logger.debug "No changes recorded but gitosis config file differs. Likely not capturing all changes."
      end

      unless conf.eql?(original)
        conf.write
      end
		end
    unless changes.empty?
      # add, commit, push, and remove local tmp dir
      changes.unshift "Updated by Redmine Gitosis"
      commit_message = changes.join("\n")
      `cd #{@local_dir} ; git add keydir/* gitosis.conf`
      `cd #{@local_dir} ; git config user.email '#{Setting.mail_from}'`
      `cd #{@local_dir} ; git config user.name 'Redmine'`
      `cd #{@local_dir} ; git commit -a -m '#{commit_message}'`
      `cd #{@local_dir} ; git push`
    end

    lockfile.flock(File::LOCK_UN)

	end

  #break the update process into parts

  # if force_clone is true current repository will be removed and re-cloned
  # @param force_clone [boolean]
  def self.initialize_gitosis_repository(force_clone = false)
    @local_dir = File.join(RAILS_ROOT,"tmp","gitosis_admin")

    if File.exist? (@local_dir)
      Rails.logger.debug "Gitosis - gitosis_admin exist"
      if force_clone
        Dir.rm_rf(@local_dir) #remove the directory and then clone it again
      else
        return
      end
    else
      Rails.logger.debug "Gitosis - gitosis_admin not exist"
    end

    # clone repo
    Rails.logger.notice "Gitosis - running: " + "env GIT_SSH='ssh -o stricthostkeychecking=no -i #{Setting.plugin_redmine_gitosis["gitosisIdentityFile"]}' git clone #{Setting.plugin_redmine_gitosis['gitosisUrl']} #{@local_dir}"
    `env GIT_SSH='ssh -o stricthostkeychecking=no -i #{Setting.plugin_redmine_gitosis["gitosisIdentityFile"]}' git clone #{Setting.plugin_redmine_gitosis['gitosisUrl']} #{@local_dir}`
  end
end
