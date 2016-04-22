require 'uri'
Puppet::Type.newtype(:pulp_repo) do
  @doc = <<-EOT
  Resource type for pulp repository
  EOT
  ensurable do
    desc <<-EOS
      Register/unregister a pulp consumer.
    EOS

    newvalue(:present) do
      provider.create
    end

    newvalue(:absent) do
      provider.destroy
    end

    defaultto :present
  end

  newparam(:id) do
    desc "uniquely identifies the repo; only alphanumeric, ., -, and _ allowed"
    isnamevar
  end

  newparam(:server) do
    desc "url of the server like https://pulp.repo"
    #use environment variable set the parameter
    defaultto ENV['PULP_SERVER']

    validate do |value|
      unless URI.parse(value).is_a?(URI::HTTP) ||
        URI.parse(value).is_a?(URI::HTTPS)
        fail("Invalid feed #{value}")
      end
    end
  end

  newparam(:api_path) do
  	desc "api path"
  	defaultto "pulp/api/v2"
  end

  newparam(:type) do
  	newvalues(:rpm, :puppet)
  	defautlto :rpm
  end

  newproperty(:name) do
  	desc "Display name for repo"
  	default to :id
  end

  newproperty(:description) do
  	desc "Description of the repository"
  	default to ''
  end

  newproperty(:feed) do
  	desc "Feed for the repository"
  	validate do |value|
  		unless URI.parse(value).is_a?(URI::HTTP) ||
  			URI.parse(value).is_a?(URI::HTTPS) ||
  			URI.parse(value).scheme == 'file'
  			fail("Invalid feed #{value}")
  		end
  	end
  end

  newproperty(:server_http) do
  	desc "Server through http"
  	newvalues(:true :false)
    #pulp default value
  	defaultto :false
  end

  newproperty(:server_https) do
  	desc "Server through http"
  	newvalues(:true, :false)
    #pulp default value
  	defaultto :true
  end

end