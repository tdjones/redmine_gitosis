require 'redmine'
require 'dispatcher'

require_dependency 'gitosis'
require_dependency 'gitosis_job' #Needed for delayed_job
require_dependency 'gitosis/patches/repositories_controller_patch'
require_dependency 'gitosis/patches/repositories_helper_patch'
require_dependency 'gitosis/patches/git_adapter_patch'

if RAILS_ENV == 'development'
  ActiveSupport::Dependencies.load_once_paths.reject!{|x| x =~ /^#{Regexp.escape(File.dirname(__FILE__))}/}
end

Redmine::Plugin.register :redmine_gitosis do
  name 'Redmine Gitosis plugin'
  author 'Jan Schulz-Hofen'
  description 'Enables Redmine to update a gitosis server.'
  version '0.0.5'
  settings :default => {
    'gitosisUrl' => 'git@localhost:gitosis-admin.git',
    'gitosisIdentityFile' => '/srv/projects/redmine/miner/.ssh/id_rsa',
    'developerBaseUrls' => 'git@www.salamander-linux.com:,https://[user]@www.salamander-linux.com/git/',
    'readOnlyBaseUrls' => 'http://www.salamander-linux.com/git/',
    'basePath' => '/srv/projects/git/repositories/',
    }, 
    :partial => 'redmine_gitosis'
  menu :account_menu, :mysshkeys, { :controller => 'gitosis_public_keys', :action => 'index' }, {:caption => 'My SSH Keys', :if => Proc.new { User.current.logged? }, :before => :my_account}
end

# initialize hook
class GitosisPublicKeyHook < Redmine::Hook::ViewListener
  render_on :view_my_account_contextual, :inline => "| <%= link_to(l(:label_public_keys), public_keys_path) %>" 
end

class GitosisProjectShowHook < Redmine::Hook::ViewListener
  render_on :view_projects_show_left, :partial => 'redmine_gitosis'
end

Dispatcher.to_prepare :redmine_gitosis do
  # apply GitAdapter patch
  unless Redmine::Scm::Adapters::GitAdapter.include?(Gitosis::Patches::GitAdapterPatch)
    Redmine::Scm::Adapters::GitAdapter.send(:include, Gitosis::Patches::GitAdapterPatch)
  end
  # apply RepositoriesController patch
  unless RepositoriesController.include?(Gitosis::Patches::RepositoriesControllerPatch)
    RepositoriesController.send(:include, Gitosis::Patches::RepositoriesControllerPatch)
  end
  # apply RepositoriesHelper patch
  unless RepositoriesHelper.include?(Gitosis::Patches::RepositoriesHelperPatch)
    RepositoriesHelper.send(:include, Gitosis::Patches::RepositoriesHelperPatch)
  end
  # initialize observer
  unless ActiveRecord::Base.observers.include?(GitosisObserver) || File.basename($0) == 'rake'
    ActiveRecord::Base.observers = ActiveRecord::Base.observers << GitosisObserver
  end
  require_dependency 'principal'
  require_dependency 'user'
  # initialize association from user -> public keys
  User.send(:has_many, :gitosis_public_keys, :dependent => :destroy)

end
