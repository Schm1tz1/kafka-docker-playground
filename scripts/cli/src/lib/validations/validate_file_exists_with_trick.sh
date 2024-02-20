## [@bashly-upgrade validations]
validate_file_exists_with_trick() {
  file="$1"

  real_file=$file
  if [[ $file == *"@"* ]]
  then
    real_file=$(echo "$file" | cut -d "@" -f 2)
  fi
  
  [[ -f "$real_file" ]] || logerror "<$real_file> does not correspond to the path of an existing file, please make sure to use absolute full path or correct relative path !"
}
