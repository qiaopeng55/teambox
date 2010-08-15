class ProjectsController < ApplicationController
  before_filter :can_modify?, :only => [:edit, :update, :transfer, :destroy]
  before_filter :load_projects, :only => [:index]
  before_filter :set_page_title
  
  def index
    @activities = Project.get_activities_for(@projects)
    @last_activity = @activities.last
    @pending_projects = @current_user.invitations.reload # adding reload to avoid a strange bug
    @archived_projects = @current_user.projects.archived

    respond_to do |f|
      f.html  { @threads = Activity.get_threads(@activities) }
      f.m
      f.rss   { render :layout  => false }
      f.xml   { render :xml     => @projects.to_xml }
      f.json  { render :as_json => @projects.to_xml }
      f.yaml  { render :as_yaml => @projects.to_xml }
      f.ics   { render :text    => Project.to_ical(@projects, params[:filter] == 'mine' ? current_user : nil, request.host, request.port) }
      f.print { render :layout  => 'print' }
    end
  end

  def show
    @activities = Project.get_activities_for @current_project
    @last_activity = @activities.last
    @pending_projects = @current_user.invitations.reload
    @recent_conversations = Conversation.not_simple.recent(4).find_all_by_project_id(@current_project.id)

    #   Use this snippet to test the notification emails that we send:
    #@project = @current_project
    #render :file => 'emailer/notify_comment', :layout => false
    #return

    respond_to do |f|
      f.html  { @threads = Activity.get_threads(@activities) }
      f.m
      f.rss   { render :layout  => false }
      f.xml   { render :xml     => @current_project.to_xml }
      f.json  { render :as_json => @current_project.to_xml }
      f.yaml  { render :as_yaml => @current_project.to_xml }
      f.ics   { render :text    => @current_project.to_ical(params[:filter] == 'mine' ? current_user : nil) }
      f.print { render :layout  => 'print' }
    end
  end
  
  def new
    @project = Project.new
    @organization = Organization.new
  end
  
  def create
    @project = current_user.projects.new(params[:project])
    @project.organization = current_user.organizations.find_by_id(params[:project][:organization_id])

    unless @project.organization
      if params[:project][:organization_name]
        @organization = Organization.new(:name => params[:project][:organization_name])
        unless @organization.save
          @project.errors.add :organization_name, ""
          render :new
          return
        end
        @organization.memberships.create!(:user_id => current_user.id, :role => Membership::ROLES[:admin])
        @project.organization = @organization
      end
    end
    
    unless current_user.can_create_project?
      flash[:error] = t('projects.new.not_allowed')
      redirect_to root_path
      return
    end
    
    respond_to do |f|
      if @project.save
        flash[:notice] = I18n.t('projects.new.created')
        f.html { redirect_to project_path(@project) }
        f.m    { redirect_to project_path(@project) }
      else
        flash.now[:error] = I18n.t('projects.new.invalid_project')
        f.html { render :new }
        f.m    { render :new }
      end
    end
  end
  
  def edit
    @sub_action = params[:sub_action] || 'settings'
  end
  
  def update
    @sub_action = params[:sub_action] || 'settings'

    if params[:project] && params[:project][:organization_id]
      unless @current_project.organization.is_admin?(current_user)
        @current_project.errors.add(:organization_id, "You're not allowed to modify projects in this organization")
        return render :edit
      end
      @current_project.organization_id = params[:project][:organization_id]
    end

    if @current_project.update_attributes(params[:project])
      flash.now[:success] = t('projects.edit.success')
    else
      flash.now[:error] = t('projects.edit.error')
    end

    render :edit
  end
  
  def transfer
    unless @current_project.owner?(current_user)
      flash[:error] = t('common.not_allowed')
      redirect_to projects_path
      return
    end
    
    # Grab new owner
    user_id = params[:project][:user_id] rescue nil
    person = @current_project.people.find_by_user_id(user_id)
    saved = false
    
    # Transfer!
    unless person.nil?
      saved = @current_project.transfer_to(person)
    end
    
    if saved
      respond_to do |f|
        flash[:notice] = I18n.t('projects.edit.transferred')
        f.html { redirect_to project_path(@current_project) }
        handle_api_success(f, @current_project)
      end
    else
      respond_to do |f|
        flash[:error] = I18n.t('projects.edit.invalid_transferred')
        f.html { redirect_to project_path(@current_project) }
        handle_api_error(f, @current_project)
      end
    end
  end

  def destroy
    @current_project.destroy
    respond_to do |f|
      f.html { redirect_to projects_path }
    end
  end

  skip_before_filter :belongs_to_project?, :only => [:join]

  def join
    if @current_project.organization.is_admin?(current_user)
      @current_project.people.create!(
        :user => current_user,
        :role => Person::ROLES[:admin])
      flash[:success] = t('projects.join.welcome')
      redirect_to project_path(@current_project)
    elsif @current_project.public
      @current_project.people.create!(
        :user => current_user,
        :role => Person::ROLES[:commenter])
      flash[:success] = t('projects.join.welcome')
      redirect_to project_path(@current_project)
    else
      render :text => "You're not authorized to join this project"
    end
  end

  protected
  
    def load_task_lists
      @task_lists = @current_project.task_lists.unarchived
    end
    
    def can_modify?
      if !( @current_project.owner?(current_user) or 
            ( @current_project.admin?(current_user) and 
              !(params[:controller] == 'transfer' or params[:sub_action] == 'ownership')))
        
          respond_to do |f|
            flash[:error] = t('common.not_allowed')
            f.html { redirect_to projects_path }
            handle_api_error(f, @current_project)
          end
        return false
      end
      
      true
    end
  
    def load_projects
      if params.has_key?(:sub_action)
        @sub_action = params[:sub_action]
        if @sub_action == 'archived'
          @projects = current_user.projects.archived
        end  
      else
        @sub_action = 'all'
        @projects = current_user.projects.unarchived
      end
    end

end