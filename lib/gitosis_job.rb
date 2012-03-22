module Gitosis
  #Use project Ids instead of Project objects to keep it out of the DB table
  class GitosisJob < Struct.new(:project_ids)
    def perform
      #Look up the projects again
      projs = Project.find_all_by_id(project_ids)
      Gitosis::update_repositories(projs)
    end
  end
end