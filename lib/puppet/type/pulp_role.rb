Puppet::Type.newtype(:pulp_role) do
  @doc = <<-EOT
  Resource type for pulp role
  EOT
  ensurable do
    desc <<-EOS
      Manage a pulp role.
    EOS

    newvalue(:present) do
      provider.create
    end

    newvalue(:absent) do
      provider.destroy
    end

    defaultto :present
  end

  newparam(:role, :namevar => true) do
    desc 'The name to identify the entry for resource permission in format login:roleid'    
  end

  newproperty(:display_name) do
  end

  newproperty(:description) do
  end
end
