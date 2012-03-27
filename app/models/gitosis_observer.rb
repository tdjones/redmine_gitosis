class GitosisObserver < ActiveRecord::Observer
  observe :project, :user, :gitosis_public_key, :member, :role, :repository
  
  
#  def before_create(object)
#    if object.is_a?(Project)
#      repo = Repository::Git.new
#      repo.url = repo.root_url = File.join(Gitosis::GITOSIS_BASE_PATH,"#{object.identifier}.git")
#      object.repository = repo
#    end
#  end
  
  def after_save(object)
    do_repositories_update(object)
  end
  def after_destroy(object)
    do_repositories_update(object)
  end
  
  protected
  
  def do_repositories_update(object)
    case object
      #Enqueue the GitosisJob based on the Object type
      when Project then Delayed::Job.enqueue Gitosis::GitosisJob.new(object.id)
      when Repository then Delayed::Job.enqueue Gitosis::GitosisJob.new(object.project.id)
      when User then Delayed::Job.enqueue Gitosis::GitosisJob.new(object.projects.collect {|p| p.id})
      when GitosisPublicKey then Delayed::Job.enqueue Gitosis::GitosisJob.new(object.user.projects.collect {|p| p.id})
      when Member then Delayed::Job.enqueue Gitosis::GitosisJob.new(object.project.id)
      when Role then Delayed::Job.enqueue Gitosis::GitosisJob.new(object.members.map(&:project).uniq.compact.collect {|p| p.id})
      else
        Rails.logger.error "Unhandled observed Model type: " + object.class.name
    end
  end
end
