#--
# Amazon Web Services EC2 Query API Ruby library
#
# Ruby Gem Name::  amazon-ec2
# Author::    Glenn Rempe  (mailto:glenn@rempe.us)
# Copyright:: Copyright (c) 2007-2008 Glenn Rempe
# License::   Distributes under the same terms as Ruby
# Home::      http://github.com/grempe/amazon-ec2/tree/master
#++

module EC2

  class Base

    #Amazon Developer Guide Docs:
    #
    # The ConfirmProductInstance operation returns true if the given product code is attached to the instance
    # with the given instance id. False is returned if the product code is not attached to the instance.
    #
    #Required Arguments:
    #
    # :product_code => String (default : "")
    # :instance_id => String (default : "")
    #
    #Optional Arguments:
    #
    # none
    #
    def confirm_product_instance( options ={} )

      options = {:product_code => "", :instance_id => ""}.merge(options)

      raise ArgumentError, "No product code provided" if options[:product_code].nil? || options[:product_code].empty?
      raise ArgumentError, "No instance ID provided" if options[:instance_id].nil? || options[:instance_id].empty?

      params = { "ProductCode" => options[:product_code], "InstanceId" => options[:instance_id] }

      return response_generator(:action => "ConfirmProductInstance", :params => params)

    end
  end

end
