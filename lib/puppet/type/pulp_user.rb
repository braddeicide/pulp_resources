
Puppet::Type.newtype(:pulp_user) do
  @doc = <<-EOT
  Resource type for pulp user
  EOT
  ensurable do
    desc <<-EOS
      Manage a pulp user.
    EOS

    newvalue(:present) do
      provider.create
    end

    newvalue(:absent) do
      provider.destroy
    end

    defaultto :present
  end

  newparam(:login, :namevar => true) do
    desc "uniquely identifies the repo; only alphanumeric, ., -, and _ allowed"    
  end

  newproperty(:display_name) do
    desc "User display name"
  end

  newproperty(:roles, :array_matching => :all) do
    desc "user roles"   
    def insync?(is)
      Puppet.debug("user roles current: #{is}, should : #{should}")
      cmp_is =is.sort.join(',')
      cmp_should=should.sort.join(',')
      return cmp_is == cmp_should
    end
  end

  newproperty(:password) do
    desc "User password"
    validate do |value|
      raise ArgumentError, "Passwords cannot include ':'" if value.is_a?(String) and value.include?(":")
    end

    def change_to_s(currentvalue, newvalue)
      if currentvalue == :absent
        return "created password"
      else
        return "changed password"
      end
    end

    def is_to_s(currentvalue)
      return '[old password hash redacted]'
    end

    def should_to_s(currentvalue)
      return '[new password hash redacted]'
    end

    def insync?(is)
      Puppet.info("User password is only set up when user created, not checked or modified afterwards.")
      return provider.exists?
    end
  end
  
  #how to auto require multiple resources
  autorequire(:pulp_role) do
    autos =[]
    unless !self[:roles] || self[:roles].empty?
      self[:roles].each do |role_id|
        autos<< role_id
      end
    end
    autos
  end

end
