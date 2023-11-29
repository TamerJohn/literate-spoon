require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "tilt/erubis"
require "redcarpet"
require "psych"

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

configure do
  enable :sessions
  set :session_secret, "secret"
end

before do
  pattern = File.join(data_path, "*")

  @files = Dir.glob(pattern).map do |path|
      File.basename(path)
  end
end

helpers do
  def signed_in?
    !!session[:username]
  end
end


# find extension of file and returns its contents formatted
def load_file_content(file_path)
  extension = File.extname(file_path)

  case extension
  when ".txt"
    response.headers["Content-Type"] = "text/plain"
    File.read(file_path)
  when ".md"
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(File.read(file_path))
  else
    session[:error] = "Sorry, the #{extension} file format is not supported yet, check back again soon!"
    redirect "/"
  end
end

# load_file_content but raw data
def raw_load_file_content(file_path)
  extension = File.extname(file_path)

  case extension
  when ".txt", ".md"
    File.read(file_path)
  else
    session[:error] = "Sorry, the #{extension} file format is not supported yet, check back again soon!"
    redirect "/"
  end
end

# Checks if file exists, creates error mesage if file does not exist.
def file_exists?(file_path)
  File.file?(file_path)
end

def valid_authentication(username, password)
  return false if username.strip == ""
  Psych.load_file("../data/users.yml")[username] == password
end

# new document form
get "/new" do
  redirect_logged_out unless signed_in?
  erb :new
end

#create a document with name argument
def create_document(file_name, content = "")
  File.open(File.join(data_path, file_name), "w") do |file|
    file.write(content)
  end
end

def valid_extension?(file_name)
  file_path = File.extname(file_name)
  file_path == ".md" || file_path == ".txt"
end

# create new document
post "/new" do
  redirect_logged_out unless signed_in?

  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)

  if file_exists?(file_path)
    session[:error] = "#{file_name} already exist!"
  elsif file_name == ""
    session[:error] = "Sorry, you must enter a file name"
  elsif !valid_extension?(file_name)
    session[:error] = "Sorry that extension is not supported yet!"
  else
    session[:success] = "#{file_name} has been created!"
    create_document(file_name)
    status 302
    redirect "/"
  end

  status 422
  erb :new
end

def redirect_logged_out
  session[:error] = "You must be signed in to do that."
  redirect "/users/login"
end

# load index and show files available in CMS
get "/" do
  redirect_logged_out unless signed_in?
  erb :index
end

#load file depending on the extension
get "/:filename" do |filename|
  redirect_logged_out unless signed_in?

  @file_path = File.join(data_path, filename)

  unless file_exists?(@file_path)
    session[:error] = "#{filename} does not exist!"
    redirect "/"
  end

  load_file_content(@file_path)
end

#display file contents to be edited
get "/:filename/edit" do
  redirect_logged_out unless signed_in?

  @filename = params[:filename]
  file_path = File.join(data_path, @filename)

  @extension = File.extname(@filename)[1..-1]

  unless file_exists?(file_path)
    session[:error] = "#{filename} does not exist!"
    redirect "/"
  end

  @file_content = raw_load_file_content(file_path)
  session[:success] = "The #{@filename} has been edited!"

  erb :edit
end

#update file contents
post "/:filename/edit" do
  redirect_logged_out unless signed_in?

  @filename = params[:filename]
  file_path = File.join(data_path, @filename)

  file_content = params[:content]

  File.write(file_path, file_content, mode: "w+")
  session[:success] = "The #{@filename} has been updated!"

  redirect "/"
end

# delete file
post "/:filename/delete" do
  redirect_logged_out unless signed_in?

  @filename = params[:filename]
  file_path = File.join(data_path, @filename)

  if params[:delete]
    session[:success] = "The #{@filename} document has been deleted!"
    File.delete(file_path)
  end

  redirect "/"
end

# display login page
get "/users/login" do
  erb :login
end

# login the user
post "/users/login" do
  @username = params[:username]
  password = params[:password]

  if valid_authentication(@username, password)
    session[:success] = "Successfully logged in as #{@username}"
    session[:username] = @username
    redirect "/"
  else
    session[:error] = "Invalid credentials"
    status 401
    erb :login
  end
end

post "/users/logout" do
  if session[:username]
    session[:username] = nil

    session[:success] = "You've been logged out"
  end

  redirect "/users/login"
end