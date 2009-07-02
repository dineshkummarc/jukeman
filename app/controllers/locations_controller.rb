class LocationsController < ApplicationController
  before_filter :load_locations, :except => [:create, :update, :destroy]
  
  def index

  end

  def show
    @location = Location.find(params[:id])

    respond_to do |format|
      format.html
      format.xml  { render :xml => @location }
    end
  end

  def new
    @location = Location.new
    @playlists = Playlist.find(:all)

    respond_to do |format|
      format.html
      format.xml  { render :xml => @location }
    end
  end

  def edit
    @playlists = Playlist.find(:all)
    @location = Location.find(params[:id])
  end

  def create
    @location = Location.new(params[:location])

    respond_to do |format|
      if @location.save
        flash[:notice] = 'Location was successfully created.'
        format.html { redirect_to(@location) }
        format.xml  { render :xml => @location, :status => :created, :location => @location }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @location.errors, :status => :unprocessable_entity }
      end
    end
  end

  def update
    @location = Location.find(params[:id])

    respond_to do |format|
      if @location.update_attributes(params[:location])
        flash[:notice] = 'Location was successfully updated.'
        format.html { redirect_to(@location) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @location.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    @location = Location.find(params[:id])
    @location.destroy

    respond_to do |format|
      format.html { redirect_to(locations_url) }
      format.xml  { head :ok }
    end
  end
  
  protected
    def load_locations
      @locations = Location.find(:all)
    end
end
