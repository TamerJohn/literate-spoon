ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "minitest/reporters"
require "rack/test"
require "fileutils"

require "pry"
require "pry-byebug"

Minitest::Reporters.use!

require_relative "../app.rb"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def session
    last_request.env["rack.session"]
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)

    create_document "about.md", "# ruby is"
    create_document "history.txt", "1993 - Yukihiro Matsumoto dreams up Ruby.\n 1995 - Ruby 0.95 released.\n 1996 - Ruby 1.0 released.\n "
    create_document "changes.txt", "2020 - Ruby 3.0 released.\n 2021 - Ruby 3.1 released.\n 2022 - Ruby 3.2 released.\n "
    create_document "xyz.xyz", "aaaaa"

    pattern = File.join(data_path, "*")

    @files = Dir.glob(pattern).map do |path|
        File.basename(path)
    end
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end


  def test_index
    get "/", {}, admin_session

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  #test non-existent files
  def test_invalid_file
    get "/notgonnahappen132323.txt", {}, admin_session

    assert_equal 302, last_response.status
    assert_equal session[:error], "notgonnahappen132323.txt does not exist!"
  end

  #test if the markdown files are display as HTML
  def test_md_file
    get "/about.md", {}, admin_session

    assert_equal 200, last_response.status
    refute_includes last_response.body, "# ruby is  "
    assert_includes last_response.body, "<h1>ruby is</h1>"
  end

  def test_unkown_extension
    get "/xyz.xyz", {}, admin_session

    assert_equal session[:error], "Sorry, the .xyz file format is not supported yet, check back again soon!"
  end


  #test the edit page
  def test_edit_page
    @files.each do |file_name|
      next if file_name == "xyz.xyz" #since file is not supported

      file_path = File.join(data_path, file_name)
      file_content = File.read(file_path)

      get "/#{file_name}/edit", {}, admin_session
      extension = File.extname(file_name)[1..-1]

      assert_equal 200, last_response.status
      assert_includes last_response.body, "Editing content of #{file_name}"
      assert_includes last_response.body, file_content
      assert_includes last_response.body, "<textarea name=\"content\" rows=\"5\" cols=\"60\" class=\"#{extension}\">#{file_content}</textarea>"
      assert_includes last_response.body, "<form action=\"/#{file_name}/edit\""
    end
  end

#test if the post method works and changes the contents of file
  def test_edit_file
    @files.each do |file_name|
      next if file_name == "xyz.xyz" #since file is not supported

      file_path = File.join(data_path, file_name)
      file_content = File.read(file_path)
      new_content = "The #{file_name} has been tampered with!" + file_content

      post "/#{file_name}/edit", {content: new_content}, admin_session
      assert_equal 302, last_response.status
      assert_equal "The #{file_name} has been updated!", session[:success]

      get "/#{file_name}"

      assert_equal 200, last_response.status
      assert_includes last_response.body, "The #{file_name} has been tampered with!"

      get "/#{file_name}/edit"
      extension = File.extname(file_name)[1..-1]

      assert_equal 200, last_response.status
      assert_includes last_response.body, "<textarea name=\"content\" rows=\"5\" cols=\"60\" class=\"#{extension}\">#{new_content}</textarea>"
      assert_includes last_response.body, "<form action=\"/#{file_name}/edit\""
    end
  end

  #test new document creation
  def test_create_new_file
    post "/new", {file_name: "test.txt"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "test.txt has been created!", session[:success]

    get last_response["Location"]

    assert_includes last_response.body, "test.txt"
    assert_equal 200, last_response.status

    get "/test.txt"
    assert_equal 200, last_response.status
  end

  # test new document creation without a valid extension
  def test_creation_valid_extension
    post "/new", {file_name: "arbitarysomething"}, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Sorry that extension is not supported yet!"
    # assert_equal "Sorry that extension is not supported yet!", session[:error]
    # The above line can not be used because session[:error] is already deleted to display the error.

    get "/"
    refute_includes last_response.body, "arbitarysomething"
  end

  #test empty string file_name

  def test_creation_empty_file_name
    post "/new", {file_name: ""}, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Sorry, you must enter a file name"
  end

  # checks if files have been deleted
  def test_deletion
    @files.each do |file_name|
      post "/#{file_name}/delete", {delete: true}, admin_session

      assert_equal 302, last_response.status
      assert_equal "The #{file_name} document has been deleted!", session[:success]

      get last_response["Location"], {}, admin_session

      refute_includes last_response.body, "/#{file_name}/edit"
    end
  end

  # test if the signin page is displaying correctly
  def test_login_page
    get "/users/login"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input type=\"text\" name=\"password\">"
    assert_includes last_response.body, "<input type=\"text\" name=\"username\" value=\""
  end

  # test if the user is notified about invalid credentials and can retry
  def test_login_invalid
    post "/users/login", username: "admin", password: "test"

    assert_equal 401, last_response.status
    assert_includes last_response.body, "Invalid credentials"

    assert_includes last_response.body, "<input type=\"text\" name=\"password\">"
    assert_includes last_response.body, "<input type=\"text\" name=\"username\" value=\"admin\""
    refute session[:loggedin]
  end

  # test if the user can sign in with the correct credentials
  def test_login_valid
    post "/users/login", username: "admin", password: "secret"

    assert_equal 302, last_response.status
    assert_equal "Successfully logged in as admin", session[:success]
    assert_equal "admin", session[:username]

    get last_response["Location"]

    assert_equal 200, last_response.status
    @files.each do |file_name|
      assert_includes last_response.body, "<a href=\"/#{file_name}/edit\">Edit</a>"
   end

    assert_includes last_response.body, "Signed in as admin"
  end

  # test if the user can signout
  def test_signout
    post "/users/logout", {}, admin_session
    assert_equal "You've been logged out", session[:success]
    assert_nil session[:username]

    get last_response["Location"]
  end

  def test_unauth_index
    get "/"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:error]

    get last_response["Location"]

    refute session[:loggedin]
    refute session[:username]
    assert_includes last_response.body, "<input type=\"text\" name=\"password\">"
    assert_includes last_response.body, "<input type=\"text\" name=\"username\""
  end

  # testin unautharized form submission and page viewing

  def test_unauth_new_file_page
    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:error]
  end

  def test_aunauth_new_file
    post "/new", file_name: "testingtestingTESTING.txt"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:error]

    get "/", {}, admin_session
    refute_includes last_response.body, "testingtestingTESTING.txt"
  end

  def test_unauth_edit_page
    get "/about.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:error]
  end

  def test_unauth_edit
    @files.each do |file_name|
      post "/#{file_name}/edit", content: "testsabcdtestefghtest"
      assert_equal 302, last_response.status
      assert_equal "You must be signed in to do that.", session[:error]
    end

    get "/", {}, admin_session

    @files.each do |file_name|
      get "/#{file_name}"
      refute_includes last_response.body, "testsabcdtestefghtest"
    end
  end

  def test_unauth_delete
    @files.each do |file_name|
      post "/#{file_name}/delete"
      assert_equal 302, last_response.status
      assert_equal "You must be signed in to do that.", session[:error]
    end
  end
end
