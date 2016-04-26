
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

  newparam(:login) do
    desc "uniquely identifies the repo; only alphanumeric, ., -, and _ allowed"
    isnamevar
  end

  newproperty(:display_name) do

  end

  newproperty(:roles, :array_matching => :all) do
    desc "user roles"
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
      return provider.exists?
    end
  end

end
