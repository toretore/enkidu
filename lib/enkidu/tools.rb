module Enkidu


  # Recursive (deep) merge of hashes and arrays
  #
  # For a hash, each key in o2 is merged onto a copy of o1. If the value is
  # a hash or an array, it is itself deep_merged before it is added.
  #
  # For arrays, a copy of o1 is made, then each value in n2 not equal to the same
  # position in n1 is pushed onto the copy. When both values are arrays or hashes,
  # they are deep_merged onto the same position as before.
  #
  # deep_merge({foo: 'bar', bingo: 'dingo'}, {baz: 'quux', bingo: 'bongo'})
  # => {foo: 'bar', bingo: 'bongo', baz: 'quux'}
  #
  # deep_merge([1, 2 {horse: 'donkey'}], [3, 4, {horse: 'rabbit', cat: 'dog'}])
  # #=> [1, 2, {horse: 'rabbit', cat: 'dog'}, 3, 4]
  def self.deep_merge(o1, o2)
    if Hash === o1 && Hash === o2
      res = o1.dup
      o2.each do |k, nv|
        ov = res[k]
        res[k] = if Hash === ov && Hash === nv
                   deep_merge(ov, nv)
                 elsif Array === ov && Array === nv
                   deep_merge(ov, nv)
                 else
                   nv
                 end
      end
    elsif Array === o1 && Array === o2
      res = o1.dup
      nvals = []
      o2.each_with_index do |nv, i|
        ov = res[i]
        if (Hash === ov && Hash === nv) || (Array === ov && Array === nv)
          res[i] = deep_merge(ov, nv)
        elsif ov != nv
          nvals << nv
        end
      end
      res.concat(nvals)
    else
      raise
    end

    res
  end


end#module Enkidu
