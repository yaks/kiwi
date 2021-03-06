class Kiwi::Resource

  def self.inherited subclass
    subclass.init
  end


  def self.init
    reroute :options, Kiwi::Resource::Resource, :get do |params|
      params[Kiwi::Resource::Resource.identifier] = self.class.name
    end

    instance_eval do
      @desc       = nil
      @identifier = nil
      @labels     = {}
      @route      = nil
      @view       = nil
      @c_label    = nil

      def method_added mname
        return unless resource_methods.include? mname
        @labels[mname] = @c_label
        @c_label = nil
      end
    end
  end


  ##
  # Add a label to the next defined public instance method:
  #   label "Update this resource!"
  #   def put(id)
  #     # do something
  #   end

  def self.label str
    @c_label = str
  end


  ##
  # Returns a mapping of method names to labels.

  def self.labels
    @labels
  end


  ##
  # Build and validate a Resource hash from a data hash.

  def self.build data, opts={}
    data = data.dup
    id = data[identifier]      ||
         data[identifier.to_s] ||
         opts[identifier]

    # TODO: Revisit this when link_to is implemented
    data[:_links]    ||= self.links(id).map(&:to_hash) if opts[:append_links]
    data[:_type]     ||= self.name
    data[identifier] ||= id if id

    view_from(data)
  end


  ##
  # An optional description for the resource.

  def self.desc string=nil
    return @desc unless string
    @desc = string
  end


  ##
  # The field used as the resource id. Defaults to :id.
  # This attribute is inherited by the superclass by default.
  # Setting it to false will re-enable the inheritance.

  def self.identifier field=nil
    @identifier = field.to_sym if field
    @identifier = nil          if field == false

    out =
      @identifier ||
      superclass.respond_to?(:identifier) && superclass.identifier ||
      :id

    out
  end


  class << self
    private
    def default_id_param # :nodoc:
      Kiwi::Param.new self.identifier, String,
        :desc => "Id of the resource"
    end
  end


  ##
  # Array of links for this resource.

  def self.links id=nil
    links = []

    resource_methods.each do |mname|
      link = link_for(mname, id)
      link.label = labels[mname]
      links << link
    end

    links
  end


  ##
  # Single link for this resource, for a method and id.

  def self.link_for mname, id=nil
    mname = mname.to_sym

    raise Kiwi::MethodNotAllowed,
      "Method not supported `#{mname}' for #{self.name}" unless
        resource_methods.include?(mname) || self.reroutes[mname]

    href = route.path.dup
    rsc_method = mname

    unless Kiwi.http_verbs.include?(mname)
      rsc_method = Kiwi.default_http_verb
      href << ".#{mname}"
    end

    href << "#{Kiwi::Route.delimiter}#{id || identifier.inspect}" if
      id_resource_methods.include?(mname)

    Kiwi::Link.new mname, href, params_for_method(mname)
  end


  ##
  # Single link to a specific resource and method. Raises a ValidationError
  # if not all required params are provided.

  def self.link_to mname, params=nil
    link_for(mname).build(params)
  end


  ##
  # The param description and validator accessor.

  def self.param &block
    @param ||= Kiwi::ParamSet.new
    @param.instance_eval(&block) if block_given?
    @param
  end


  ##
  # An array of param validators for the given method.

  def self.params_for_method mname
    params = param.for_method(mname)

    params.unshift default_id_param if !param[self.identifier] &&
                                        id_resource_methods.include?(mname)

    params
  end


  ##
  # The list of methods to return as resource links if
  # defined as instance methods.

  def self.resource_methods
    public_instance_methods - Kiwi::Resource.public_instance_methods
  end


  ##
  # The expected type of response and request method for each resource_method.

  def self.id_resource_methods
    #@id_resource_methods ||= [:get, :put, :patch, :delete]
    resource_methods.select do |mname|
      prm = public_instance_method(mname).parameters[0]

      prm && prm.any?{|name| name.to_s == identifier.to_s } ||
        param.for_method(mname).any?{|attr| attr.name == identifier.to_s }
    end
  end


  ##
  # Reroute a method call to a different resource and not trigger the view
  # validation. Used to implement the OPTION method:
  #   reroute :option, LinkResource, :list do |params|
  #     params.clear
  #     params[:resource] = self.class.route
  #   end
  #
  # If a resource public instance method of the same name is defined,
  # reroute will be ignored in favor of executing the method.

  def self.reroute mname, resource_klass, new_mname=nil, &block
    self.reroutes[mname.to_sym] = {
      :resource => resource_klass,
      :method   => (new_mname || mname).to_sym,
      :proc     => block
    }
  end


  ##
  # Hash list of all reroutes.

  def self.reroutes
    @reroutes ||= {}
  end


  ##
  # The route to access this resource. Defaults to the underscored version
  # of the class name. Pass multiple parts as arguments to use the preset
  # Kiwi route delimiter:
  #   MyResource.route "foo", "bar"
  #   #=> "/foo/bar"

  def self.route *parts
    return @route if @route && parts.empty?

    if parts.empty?
      new_route = self.name.gsub(/([A-Za-z0-9])([A-Z])/,'\1_\2').downcase
      parts     = new_route.split("::")
    end

    @route = Kiwi::Route.new(*parts) do |key|
      next if key == Kiwi::Route.tmp_id
      self.param.string key
    end
  end


  ##
  # Check if this resource routes the given path.

  def self.routes? path
    self.route.routes? path
  end


  ##
  # Define the view to render for this resource.
  # Used by default on all methods but list.

  def self.view view_class=nil
    return @view unless view_class
    @view = view_class
  end


  ##
  # Create a resource view from the given data.

  def self.view_from data
    view && view.build(data) || data
  end


  ##
  # Create a hash for display purposes.

  def self.to_hash
    out = {
      :name       => self.name,
      :details    => Kiwi::Resource::Resource.link_to(:get,
        Kiwi::Resource::Resource.identifier => self.name).to_hash,
      :links      => self.links.map(&:to_hash),
      :attributes => self.view.to_a
    }
    out[:desc] = @desc if @desc
    out
  end


  ##
  # New Resource instance with the app object that called it.

  def initialize app=nil
    @app          = app
    @append_links = false
  end


  ##
  # Sets flag to add links to the response.

  def append_links
    @append_links = true
  end


  ##
  # Call the resource with a method name and params.

  def call mname, path, params
    params = merge_path_params! path, params
    return follow_reroute(mname, params) if reroute? mname

    @params, args = validate! mname, path, params
    data = __send__(mname, *args)

    return unless data

    opts = {
      self.class.identifier => @params[self.class.identifier],
      :append_links => @append_links
    }

    if Array === data
      data = data.map do |item|
        self.class.build item, opts
      end

    else
      data = self.class.build data, opts
    end

    data
  end


  ##
  # Validate the incoming request. Returns the validated params hash
  # and the arguments for the method.

  def validate! mname, path, params
    meth = resource_method mname

    raise Kiwi::MethodNotAllowed,
      "Method not supported `#{mname}' for #{self.class.name}" unless meth

    params = self.class.param.validate! mname, params
    args   = meth.parameters.map{|(_, name)| params[name.to_s]}

    [params, args]

  rescue Kiwi::InvalidParam => e
    raise Kiwi::BadRequest,
      "#{e.message} for #{self.class.name}##{mname}"
  end


  ##
  # Returns a resource method instance. Similar to public_method.

  def resource_method name
    return unless resource_methods.include?(name.to_sym)
    public_method name
  end


  ##
  # Shortcut for self.class.resource_methods.

  def resource_methods
    @resource_methods ||= self.class.resource_methods
  end


  private


  def reroute? mname
    self.class.reroutes[mname] && !resource_methods.include?(mname)
  end


  def follow_reroute mname, params={}
    rdir = self.class.reroutes[mname]
    instance_exec(params, &rdir[:proc]) if rdir[:proc]

    rdir[:resource].new(@app).call rdir[:method], params
  end


  ##
  # Merge the params from the path into the params hash.

  def merge_path_params! path, params={}
    path_params = self.class.route.parse(path)

    params[self.class.identifier] = path_params.delete(Kiwi::Route.tmp_id) if
      path_params.has_key?(Kiwi::Route.tmp_id)

    params.merge( path_params )
  end


  identifier :id
  require 'kiwi/resource/resource'
  init
end
