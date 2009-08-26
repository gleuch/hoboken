require 'rubygems'
require 'sinatra'

require "sinatra-authentication"

configure do
  %w(dm-core dm-is-versioned dm-timestamps dm-tags wikitext article).each { |lib| require lib }

  ROOT = File.expand_path(File.dirname(__FILE__))
  config = begin
    YAML.load(File.read("#{ROOT}/config.yml").gsub(/ROOT/, ROOT))[Sinatra::Application.environment.to_s]
  rescue => ex
    raise "Cannot read the config.yml file at #{ROOT}/config.yml - #{ex.message}"
  end

  DataMapper.setup(:default, config['db_connection'])
  DataMapper.auto_upgrade!

  PARSER = Wikitext::Parser.new(:external_link_class => 'external', :internal_link_prefix => nil)
  
  # Set to true if user must login before create/edit
  REQUIRE_LOGIN = false
end

helpers do
  # break up a CamelCased word into something more readable
  # this is used when you create a new page by visiting /NewItem
  def de_wikify(phrase)
    phrase.gsub(/(\w)([A-Z])/, "\\1 \\2")
  end

  def friendly_time(time)
    time.strftime("%a. %b. %d, %Y, %I:%M%p")
  end
end

get '/' do
  @article = Article.first_or_create(:slug => 'Index')
  @recent = Article.all(:order => [:updated_at.desc], :limit => 10)
  haml :show
end

post '/' do
  @article = Article.first_or_create(:slug => params[:slug])
  unless params[:preview] == '1'
    @article.update_attributes(:title => params[:title], :body => params[:body], :slug => params[:slug], :tag_list => params[:tag_list])
    redirect "/#{params[:slug].gsub(/^index$/i, '')}"
  else
    haml :edit, :locals => {:action => ["Editing", "Edit"]}
  end
end

get '/search' do
  unless params[:q].blank?
    q, page, per_page = params[:q].downcase, params[:page] || 1, 20

    # Search across page, give higher rank on title.
    # TODO : Fix problem w/ order in datamapper (prob custom sql query)
    search = ["(LOWER(title) LIKE ? OR LOWER(body) LIKE ?)", "%#{q}%", "%#{q}%"]
    order = [:created_at.desc]
    #order = ["((CASE WHEN LOWER(title) LIKE ? THEN 2 ELSE 0 END) + (CASE WHEN LOWER(body) LIKE ? THEN 1 ELSE 0 END)), created_at DESC", "%#{q}%", "%#{q}%"]

    @results = Article.all(:order => order, :conditions => search)
  end

  haml :search
end

get '/tags/:tag_name' do
  tag = Tag.first(:name => params[:tag_name])
  @tagged_articles = Tagging.all(:tag_id => tag.id, :order => [:id.desc]).map{|t| t.taggable}
  @title = "Items tagged &quot;#{params[:tag_name]}&quot;"
  haml :show_tag
end

get '/:slug' do
  @article = Article.first(:slug => params[:slug])
  if @article
    haml :show
  else
    login_required if REQUIRE_LOGIN

    @article = Article.new(:slug => params[:slug], :title => de_wikify(params[:slug]))
    haml :edit, :locals => {:action => ["Creating", "Create"]}
  end
end

get '/:slug/history' do
  @article = Article.first(:slug => params[:slug])
  haml :history
end

get '/:slug/edit' do
  login_required if REQUIRE_LOGIN

  @article = Article.first(:slug => params[:slug])
  haml :edit, :locals => {:action => ["Editing", "Edit"]}
end

post '/:slug/edit' do
  login_required if REQUIRE_LOGIN

  @article = Article.first(:slug => params[:slug])
  @article.body = params[:body] if params[:body]
  haml :revert
end