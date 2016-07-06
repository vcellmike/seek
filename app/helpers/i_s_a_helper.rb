require 'tempfile'

module ISAHelper

  FILL_COLOURS = {'Sop'=>"#7ac5cd", #cadetblue3
                  'Model'=>"#cdcd00", #yellow3
                  'DataFile'=>"#eec591", #burlywood2
                  'Investigation'=>"#E6E600",
                  'Study'=>"#B8E62E",
                  'Assay'=> {'EXP'=>"#64b466",'MODEL'=>"#92CD00"},
                  'Publication'=>"#84B5FD",
                  'Presentation' => "#8ee5ee", #cadetblue2
                  'HiddenItem' => "#d3d3d3"} #lightgray

  BORDER_COLOURS = {'Sop'=>"#619da4",
                    'Model'=>"#a4a400",
                    'DataFile'=>"#be9d74",
                    'Investigation'=>"#9fba99",
                    'Study'=>"#74a06f",
                    'Assay'=> {'EXP'=>"#509051",'MODEL'=>"#74a400"},
                    'Publication'=>"#6990ca",
                    'Presentation' => "#71b7be", #cadetblue2
                    'HiddenItem' => "#a8a8a8"}

  FILL_COLOURS.default = "#8ee5ee" #cadetblue2
  BORDER_COLOURS.default = "#71b7be"

  def cytoscape_elements elements_hash
    begin
      cytoscape_node_elements(elements_hash[:nodes]) + cytoscape_edge_elements(elements_hash[:edges])
    rescue Exception=>e
      raise e if Rails.env.development?
      Rails.logger.error("Error generating nodes and edges for the graph - #{e.message}")
      {:error => 'error'}
    end
  end

  def reduced_elements elements, max_node_number, force_max_node, root_element, current_element=nil
    current_element||=root_element
    nodes = elements.select{|e| e[:group] == 'nodes'}
    edges = elements.select{|e| e[:group] == 'edges'}
    if nodes.size > max_node_number
      current_element_id = node_id(current_element)
      current_node = elements.select{|e| e[:group] == 'nodes' && e[:data][:id] == current_element_id }.first

      connected_edges = edges.select{|e| e[:data][:source] == current_element_id || e[:data][:target] == current_element_id}
      connected_edge_sources = connected_edges.collect{|e| e[:data][:source]}
      connected_edge_targets = connected_edges.collect{|e| e[:data][:target]}
      connected_edge_ids = (connected_edge_sources + connected_edge_targets).uniq

      connected_nodes = nodes.select{|e| connected_edge_ids.include?(e[:data][:id]) && e[:data][:id] != current_element_id}
      reduced_nodes = connected_nodes + [current_node]

      reduced_edges = possible_edges_for reduced_nodes, edges

      reduced_elements = reduced_nodes + reduced_edges

      if force_max_node && reduced_nodes.size > max_node_number
        max_elements_from(reduced_elements, max_node_number, current_node)
      else
        reduced_elements
      end
    else
      elements
    end
  end

  private

  #getting the nodes equal to the max_node_number, with the priority for the parent nodes
  def max_elements_from(reduced_elements, max_node_number, current_node)
    max_nodes = [current_node]
    connected_nodes = reduced_elements.select{|e| e[:group] == 'nodes'}.reject {|element| element[:data][:id] == current_node[:data][:id] }
    connected_edges = reduced_elements.select{|e| e[:group] == 'edges'}
    connected_edge_sources = connected_edges.collect{|e| e[:data][:source]}.uniq
    #put the parent nodes in front
    connected_nodes.sort!{|a,b| connected_edge_sources.find_index(b[:data][:id]).to_i <=> connected_edge_sources.find_index(a[:data][:id]).to_i}
    max_nodes |= connected_nodes.take(max_node_number-1)

    max_edges = possible_edges_for max_nodes, connected_edges
    max_elements = max_nodes + max_edges
    max_elements
  end

  #get all the edges for nodes from the edge collection.
  #not only the edges that connect current node to other node
  def possible_edges_for nodes, edge_collection
    possible_edges = []
    node_ids = nodes.collect{|node| node[:data][:id]}
    edge_collection.each do |edge|
      source = edge[:data][:source]
      target = edge[:data][:target]
      if node_ids.include?(source) && node_ids.include?(target)
        possible_edges << edge
      end
    end
    possible_edges
  end

  def cytoscape_node_elements nodes
    cytoscape_node_elements = []
    nodes.each do |node|
      item = node
      item_type = node.class.name
      n_id = node_id(node)
      image_url = nil

      if item.can_view?
        description = item.respond_to?(:description) ? item.description : ''
        no_description_text = item.kind_of?(Publication) ? 'No abstract' : 'No description'
        tt = description.blank? ? no_description_text : truncate(h(description), :length => 500)
        image_url = resource_avatar_path(item)
        url = polymorphic_path(item)
        #distinquish two assay classes
        if item.kind_of?(Assay)
          assay_class_title = item.assay_class.title
          assay_class_key = item.assay_class.key
          name = truncate(h(item.title), :length => 110)
          item_info = link_to("<b>#{assay_class_title}: </b>".html_safe +  h(item.title), polymorphic_path(item), 'data-tooltip' => tooltip(tt))
          fave_color = FILL_COLOURS[item_type][assay_class_key] || FILL_COLOURS.default
          border_color = BORDER_COLOURS[item_type][assay_class_key] || BORDER_COLOURS.default
        else
          name = truncate(h(item.title), :length => 110)
          item_info = link_to("<b>#{item_type.humanize}: </b>".html_safe +  h(item.title), polymorphic_path(item), 'data-tooltip' => tooltip(tt))
          fave_color = FILL_COLOURS[item_type] || FILL_COLOURS.default
          border_color = BORDER_COLOURS[item_type] || BORDER_COLOURS.default
        end
      else
        name = 'Hidden item'
        item_info = hidden_items_html([item], 'Hidden item')
        fave_color = FILL_COLOURS['HiddenItem'] || FILL_COLOURS.default
        border_color = BORDER_COLOURS['HiddenItem'] || BORDER_COLOURS.default
      end
      cytoscape_node_elements << node_element(n_id, name, item_info, fave_color, border_color, url, image_url)
    end
    cytoscape_node_elements
  end

  def cytoscape_edge_elements edges
    cytoscape_edge_elements = []
    edges.each do |edge|
      source_item, target_item = edge
      source = node_id(source_item)
      target = node_id(target_item)
      target_type = target_item.class.name
      e_id = edge_id(source_item, target_item)
      name = edge_label(source_item, target_item)

      if target_item.can_view?
        if target_item.kind_of?(Assay)
          fave_color = BORDER_COLOURS[target_type][target_item.assay_class.key] || BORDER_COLOURS.default
        else
          fave_color = BORDER_COLOURS[target_type] || BORDER_COLOURS.default
        end
      else
        fave_color = BORDER_COLOURS['HiddenItem'] || BORDER_COLOURS.default
      end
      cytoscape_edge_elements << edge_element(e_id, name, source, target, fave_color)
    end
    cytoscape_edge_elements
  end

  def node_element id, name, item_info, fave_color, border_color, url, image_url = nil
    hash = {:group => 'nodes',
     :data => {:id => id,
               :name => name,
               :item_info => item_info,
               :faveColor => fave_color,
               :borderColor => border_color,
               :url => url}
    }
    if image_url
      hash[:data][:imageUrl] = asset_path(image_url)
    end

    hash
  end

  def edge_element id, name, source, target, fave_color
    {:group => 'edges',
     :data => {:id => id,
               :name => name,
               :source => source,
               :target => target,
               :faveColor => fave_color}
    }
  end

  def edge_label source,target
    source_type,source_id = source.class.name, source.id
    target_type,target_id = target.class.name, target.id

    label_data = []
    if source_type == 'Assay' && (target_type == 'DataFile' || target_type == 'Sample')
      assay_asset = AssayAsset.where(["assay_id=? AND asset_id=?", source_id, target_id]).first
      if assay_asset
        label_data << assay_asset.relationship_type.title if assay_asset.relationship_type
        label_data << direction_name(assay_asset.direction) if (assay_asset.direction && assay_asset.direction != 0)
      end
    elsif source_type == 'Sample' && target_type == 'Assay'
      assay_asset = AssayAsset.where(["assay_id=? AND asset_id=?", target_id, source_id]).first
      if assay_asset
        label_data << direction_name(assay_asset.direction) if (assay_asset.direction && assay_asset.direction != 0)
      end
    end
    label_data.join(', ')
  end

  private

  def node_id(object)
    "#{object.class.name}-#{object.id}"
  end

  def edge_id(source, target)
    "#{node_id(source)}-#{node_id(target)}"
  end

end
