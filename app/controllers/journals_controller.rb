require 'date'
class JournalsController < ApplicationController
  # Journals API: Simply ask for all journals since a certain date/time.
  def index
    @journals = if params[:since]
      Journal.find(:all, :conditions => ["created_at > ?", Time.parse(params[:since]).strftime("%Y-%m-%d %H:%M:%S")])
    else
      Journal.find(:all)
    end

    respond_to do |format|
      format.xml  { render :xml => @journals }
      format.json { render :json => @journals }
    end
  end
end
