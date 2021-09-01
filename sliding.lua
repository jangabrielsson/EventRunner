function sampler(size)
  local sum,n,average=0,0
  return function(x)
    sum,n=sum+x,n+1
    average = sum/n
    if n >= size then 
      sum,n=sum-average,n-1
    end
    return average
  end
end

local samp = sampler(40)
for i=1,10000 do
  print(samp(math.random(1,500)))
end