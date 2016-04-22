require 'json'
require 'puppet'
require 'inifile'
require 'openssl'
Puppet::Type.type(:pulp_repo).provide(:cli) do

  desc "Manage pulp repo with command line utilities"
  commands :pulpadmin => 'pulp-admin'
  commands :curl => 'curl'

  def initialize(value={})
    super(value)
    @property_flush = {}
    #login fetch user certificate
    login_get_cert
  end
  mk_resources_methods

  def self.instances
    login_get_cert

    repos =[]
    execpipe([command(:curl),  '-k', '--cert' , '~/.pulp/user-cert.pem',  "#{@resource[:server]}/#{@resources[:api_path]}/repositories/?details=true"]) do |output|
      repo_raw_json= JSON.parse(output)
      #An array returned
      repo_json = repo_raw_json[0]

      repo_json.each do |repo|
        data_hash ={}
        data_hash[:id] = repo['id']
        data_hash[:display_name] = repo['display_name']
        data_hash[:description] = repo['description']
        data_hash[:server] = @resource[:server]
        data_hash[:api_path] = @resource[:api_path]
        if repo['importers']
          repo['importers'].each do |importer|
            if importer['config']
              data_hash[:feed]=importer['config']['feed']
            end
          end
        end

        if repo['distributors']
          repo['distributors'].each do |distributor|
            if distributor['distributor_type_id'] == 'yum_distributor'
              data_hash[:server_http] = distributor['config']['http']
              data_hash[:server_https] = distributor['config']['https']
            end
          end
        end
        data_hash[:ensure] = 'present'
        data_hash[:provider] = self.name
        repos << data_hash unless data_hash.empty?
      end
    end
    repos
  end

  def self.prefetch(repos)
    instances.each do |prov|
      if r = repos[prov.name]
        r.provider = prov
      end
    end
  end

  def exsits?
    @property_hash[:ensure] == :present
  end

  def create

    login_get_cert

    execoutput(repo_create_cmd)
    @property_hash[:ensure] = :present
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot create repo : #{repo_create_cmd}"
  end

  def destroy
    login_get_cert

    execoutput(repo_delete_cmd)
    @property_hash.clear
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot delete repo : #{repo_delet_cmd}"
  end

  def name=(value)
    @property_flush(:name) = value
  end

  def description=(value)
    @property_flush(:description) = value
  end

  def feed=(value)
    @property_flush(:feed) = value
  end

  def serve_http=(value)
    @property_flush(:serve_http) = value
  end

  def serve_https=(value)
    @property_flush(:serve_https) = value
  end

  def flush
    options=[]
    if @property_flush
      options << '--display-name' << @resources[:name] if @property_flush[:name]
      options << '--discription' << @resources[:description] if @property_flush[:description]
      options << '--feed' << @resources[:feed] if @property_flush[:feed]
      options << '--serve-http' << @resources[:serve_http] if @property_flush[:serve_https]
      options << '--serve-https' << @resources[:serve_http] if @property_flush[:serve_https]
    end
    unless options.empty?
      login_get_cert
      execoutput(repo_update_cmd(options))
    end
  end

  private

  def repo_create_cmd()
    repo_create=[command(:pulpadmin), "#{@resources[:type]}", "repo", "create" , "--repo-id", "#{@resources[:id]}" ]
    if @resources[:feed]
      repo_create = repoo_create + ["--feed", "#{@resources[:feed]}"]
    end
    if @resources[:serve_http]
      repo_create = repoo_create + ["--server-http", "#{@resources[:serve_http]}"]
    end
    if @resources[:serve_https]
      repo_create = repoo_create + ["--server-https", "#{@resources[:serve_https]}"]
    end
    repo_create
  end

  def repo_delete_cmd()
    [command(:pulpadmin), @resources[:type], "repo", "delete", "--bg", "--repo-id", @resources[:id]]
  end

  def repo_update_cmd(options)
    [command(:pulpadmin), @resources[:type], "repo", "update","--bg", "--repo-id", @resources[:id] ]+options
  end
  #assume user have ~/.pulp/admin setup with auth username and password
  #[auth]
  #username:
  #password:
  def login_get_cert
    unless is_cert_valid?
      unless @credentials
        @credentials= get_auth_credetials
      end
      execoutput([command(:pulpadmin), 'login', '-u', @credentials['username'], '-p', @credentials['password']])
    end
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Check ~/.pulp/admin.conf for credentials, could not log in with pulpadmin: #{detail}"
  end

  def get_auth_credetials
    admin_conf=File.expand_path("~/.pulp/admin.conf")
    admin_ini = IniFile.load(admin_conf)
    if !admin_ini['auth'] || admin_ini['auth'].empty?
      raise Puppet::Error, "Check ~/.pulp/admin.conf for auth config"
      admin_ini['auth']
    end

    def is_cert_valid?
      unless @date_after
        cert_path = File.expand_path("~/.pulp/user-cert.pem")
        if !File.exsit?(cert_path)
          return false
        end
        raw_cert = File.read cert_path
        cert_file = OpenSSL::X509::Certificate.new raw_cert
        @date_after = cert_file.not_after
        @date_before = cert_file.not_before
      end
      current_time = Time.now
      if current_time.to_i < @date_after.to_i - 600 && current_time.to_i > @date_before.to_i
        return true
      else
        return false
      end

    end
