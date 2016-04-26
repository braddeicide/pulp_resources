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

  newproperty(:type) do
    desc "Type of repo"
  	newvalues(:rpm, :puppet)
  	defaultto :rpm
  end

  newproperty(:display_name) do
  	desc "Display name for repo"
  end

  newproperty(:description) do
  	desc "Description of the repository"
  	defaultto ''
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

  newproperty(:serve_http) do
  	desc "Server through http"
  	newvalues(:true,:false)
    #pulp default value
  	defaultto :false
  end

  newproperty(:serve_https) do
  	desc "Server through http"
  	newvalues(:true, :false)
    #pulp default value
  	defaultto :true
  end

end
