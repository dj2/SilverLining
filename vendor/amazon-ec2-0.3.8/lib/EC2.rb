#--
# Amazon Web Services EC2 Query API Ruby library
#
# Ruby Gem Name::  amazon-ec2
# Author::    Glenn Rempe  (mailto:glenn@rempe.us)
# Copyright:: Copyright (c) 2007-2008 Glenn Rempe
# License::   Distributes under the same terms as Ruby
# Home::      http://github.com/grempe/amazon-ec2/tree/master
#++

%w[ base64 cgi openssl digest/sha1 net/https rexml/document time ostruct ].each { |f| require f }

# Require any lib files that we have bundled with this Ruby Gem in the lib/EC2 directory.
# Parts of the EC2 module and Base class are broken out into separate
# files for maintainability and are organized by the functional groupings defined
# in the EC2 API developers guide.
Dir[File.join(File.dirname(__FILE__), 'EC2/**/*.rb')].sort.each { |lib| require lib }

module EC2

  # Which host FQDN will we connect to for all API calls to AWS?
  # If EC2_URL is defined in the users ENV we can use that. It is
  # expected that this var is set with something like:
  #   export EC2_URL='https://ec2.amazonaws.com'
  #
  if ENV['EC2_URL']
    EC2_URL = ENV['EC2_URL']
    VALID_HOSTS = ['https://ec2.amazonaws.com', 'https://us-east-1.ec2.amazonaws.com', 'https://eu-west-1.ec2.amazonaws.com']
    raise ArgumentError, "Invalid EC2_URL environment variable : #{EC2_URL}" unless VALID_HOSTS.include?(EC2_URL)
    DEFAULT_HOST = URI.parse(EC2_URL).host
  else
    # default US host
    DEFAULT_HOST = 'ec2.amazonaws.com'
  end

  # This is the version of the API as defined by Amazon Web Services
  API_VERSION = '2008-12-01'

  # Builds the canonical string for signing. This strips out all '&', '?', and '='
  # from the query string to be signed.
  #   Note:  The parameters in the path passed in must already be sorted in
  #   case-insensitive alphabetical order and must not be url encoded.
  def EC2.canonical_string(params, host = DEFAULT_HOST, method="POST", base="/")
    # Sort, and encode parameters into a canonical string.
    sorted_params = params.sort {|x,y| x[0] <=> y[0]}
    encoded_params = sorted_params.collect do |p|
      encoded = (CGI::escape(p[0].to_s) +
                 "=" + CGI::escape(p[1].to_s))
      # Ensure spaces are encoded as '%20', not '+'
      encoded.gsub('+', '%20')
    end
    sigquery = encoded_params.join("&")

    # Generate the request description string
    req_desc =
      method + "\n" +
      host + "\n" +
      base + "\n" +
      sigquery

  end

  # Encodes the given string with the secret_access_key, by taking the
  # hmac-sha1 sum, and then base64 encoding it.  Optionally, it will also
  # url encode the result of that to protect the string if it's going to
  # be used as a query string parameter.
  def EC2.encode(secret_access_key, str, urlencode=true)
    digest = OpenSSL::Digest::Digest.new('sha1')
    b64_hmac =
      Base64.encode64(
        OpenSSL::HMAC.digest(digest, secret_access_key, str)).gsub("\n","")

    if urlencode
      return CGI::escape(b64_hmac)
    else
      return b64_hmac
    end
  end


  #Introduction:
  #
  # The library exposes one main interface class, 'EC2::Base'.
  # This class provides all the methods for using the EC2 service
  # including the handling of header signing and other security issues .
  # This class uses Net::HTTP to interface with the EC2 Query API interface.
  #
  #Required Arguments:
  #
  # :access_key_id => String (default : "")
  # :secret_access_key => String (default : "")
  #
  #Optional Arguments:
  #
  # :use_ssl => Boolean (default : true)
  # :server => String (default : 'ec2.amazonaws.com')
  # :proxy_server => String (default : nil)
  #
  class Base

    attr_reader :use_ssl, :server, :proxy_server, :port

    def initialize( options = {} )

      options = { :access_key_id => "",
                  :secret_access_key => "",
                  :use_ssl => true,
                  :server => DEFAULT_HOST,
                  :proxy_server => nil
                  }.merge(options)

      @server = options[:server]
      @proxy_server = options[:proxy_server]
      @use_ssl = options[:use_ssl]

      raise ArgumentError, "No :access_key_id provided" if options[:access_key_id].nil? || options[:access_key_id].empty?
      raise ArgumentError, "No :secret_access_key provided" if options[:secret_access_key].nil? || options[:secret_access_key].empty?
      raise ArgumentError, "No :use_ssl value provided" if options[:use_ssl].nil?
      raise ArgumentError, "Invalid :use_ssl value provided, only 'true' or 'false' allowed" unless options[:use_ssl] == true || options[:use_ssl] == false
      raise ArgumentError, "No :server provided" if options[:server].nil? || options[:server].empty?
      
      if options[:port]
        # user-specified port
        @port = options[:port]
      elsif @use_ssl
        # https
        @port = 443
      else
        # http
        @port = 80
      end

      @access_key_id = options[:access_key_id]
      @secret_access_key = options[:secret_access_key]

      # Use proxy server if defined
      # Based on patch by Mathias Dalheimer.  20070217
      proxy = @proxy_server ? URI.parse(@proxy_server) : OpenStruct.new
      @http = Net::HTTP::Proxy( proxy.host,
                                proxy.port,
                                proxy.user,
                                proxy.password).new(options[:server], @port)

      @http.use_ssl = @use_ssl

      # Don't verify the SSL certificates.  Avoids SSL Cert warning in log on every GET.
      @http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    end


    private

      # pathlist is a utility method which takes a key string and and array as input.
      # It converts the array into a Hash with the hash key being 'Key.n' where
      # 'n' increments by 1 for each iteration.  So if you pass in args
      # ("ImageId", ["123", "456"]) you should get
      # {"ImageId.1"=>"123", "ImageId.2"=>"456"} returned.
      def pathlist(key, arr)
        params = {}
        arr.each_with_index do |value, i|
          params["#{key}.#{i+1}"] = value
        end
        params
      end


      # Make the connection to AWS EC2 passing in our request.  This is generally called from
      # within a 'Response' class object or one of its sub-classes so the response is interpreted
      # in its proper context.  See lib/EC2/responses.rb
      def make_request(action, params, data='')

        @http.start do

          # remove any keys that have nil or empty values
          params.reject! { |key, value| value.nil? or value.empty?}

          params.merge!( {"Action" => action,
                          "SignatureVersion" => "2",
                          "SignatureMethod" => 'HmacSHA1',
                          "AWSAccessKeyId" => @access_key_id,
                          "Version" => API_VERSION,
                          "Timestamp"=>Time.now.getutc.iso8601} )

          sig = get_aws_auth_param(params, @secret_access_key, @server)

          query = params.sort.collect do |param|
            CGI::escape(param[0]) + "=" + CGI::escape(param[1])
          end.join("&") + "&Signature=" + sig

          req = Net::HTTP::Post.new("/")
          req.content_type = 'application/x-www-form-urlencoded'
          req['User-Agent'] = "github-amazon-ec2-ruby-gem"

          response = @http.request(req, query)

          # Make a call to see if we need to throw an error based on the response given by EC2
          # All error classes are defined in EC2/exceptions.rb
          ec2_error?(response)

          return response

        end

      end

      # Set the Authorization header using AWS signed header authentication
      def get_aws_auth_param(params, secret_access_key, server)
        canonical_string =  EC2.canonical_string(params, server)
        encoded_canonical = EC2.encode(secret_access_key, canonical_string)
      end

      # allow us to have a one line call in each method which will do all of the work
      # in making the actual request to AWS.
      def response_generator( options = {} )

        options = {
          :action => "",
          :params => {}
        }.merge(options)

        raise ArgumentError, ":action must be provided to response_generator" if options[:action].nil? || options[:action].empty?

        http_response = make_request(options[:action], options[:params])
        http_xml = http_response.body
        return Response.parse(:xml => http_xml)

      end

      # Raises the appropriate error if the specified Net::HTTPResponse object
      # contains an Amazon EC2 error; returns +false+ otherwise.
      def ec2_error?(response)

        # return false if we got a HTTP 200 code,
        # otherwise there is some type of error (40x,50x) and
        # we should try to raise an appropriate exception
        # from one of our exception classes defined in
        # exceptions.rb
        return false if response.is_a?(Net::HTTPSuccess)

        # parse the XML document so we can walk through it
        doc = REXML::Document.new(response.body)

        # Check that the Error element is in the place we would expect.
        # and if not raise a generic error exception
        unless doc.root.elements['Errors'].elements['Error'].name == 'Error'
          raise Error, "Unexpected error format. response.body is: #{response.body}"
        end

        # An valid error response looks like this:
        # <?xml version="1.0"?><Response><Errors><Error><Code>InvalidParameterCombination</Code><Message>Unknown parameter: foo</Message></Error></Errors><RequestID>291cef62-3e86-414b-900e-17246eccfae8</RequestID></Response>
        # AWS EC2 throws some exception codes that look like Error.SubError.  Since we can't name classes this way
        # we need to strip out the '.' in the error 'Code' and we name the error exceptions with this
        # non '.' name as well.
        error_code    = doc.root.elements['Errors'].elements['Error'].elements['Code'].text.gsub('.', '')
        error_message = doc.root.elements['Errors'].elements['Error'].elements['Message'].text

        # Raise one of our specific error classes if it exists.
        # otherwise, throw a generic EC2 Error with a few details.
        if EC2.const_defined?(error_code)
          raise EC2.const_get(error_code), error_message
        else
          raise EC2::Error, error_message
        end

      end

  end

end
