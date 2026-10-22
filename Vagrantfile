# -- mode: ruby --
require 'yaml'
require 'fileutils'

GROUPE  = 1                              # numéro de groupe 1
NB_APP  = (ENV['NB_APP'] || 2).to_i      # nombre de serveurs applicatifs
RESEAU  = "192.168.#{55 + GROUPE}"
VIP     = "#{RESEAU}.5"                  # IP virtuelle portée par le LB actif
BOITE   = "bento/ubuntu-24.04"
VERSION = "202404.26.0"

# Source unique de vérité : le Vagrantfile ET la configuration du
# répartiteur sont engendrés à partir de cette table.
NOEUDS = []
NOEUDS << { nom: "bdd1", ip: "#{RESEAU}.31", mem: 768, role: "bdd" }
NOEUDS << { nom: "bdd2", ip: "#{RESEAU}.32", mem: 768, role: "replique" }
(1..NB_APP).each do |i|
  NOEUDS << { nom: "app#{i}", ip: "#{RESEAU}.#{20 + i}", mem: 512, role: "app" }
end
NOEUDS << { nom: "lb1", ip: "#{RESEAU}.11", mem: 512, role: "lb", etat: "MASTER" }
NOEUDS << { nom: "lb2", ip: "#{RESEAU}.12", mem: 512, role: "lb", etat: "BACKUP" }

# Les scripts liront ce fichier dans /vagrant/config/noeuds.yml
FileUtils.mkdir_p("config")
File.write("config/noeuds.yml", {
  "reseau" => "#{RESEAU}.0/24",
  "vip"    => VIP,
  "noeuds" => NOEUDS.map { |n| n.transform_keys(&:to_s) }
}.to_yaml)

Vagrant.configure("2") do |config|
  config.vm.box         = BOITE
  config.vm.box_version = VERSION

  NOEUDS.each do |n|
    config.vm.define n[:nom] do |m|
      m.vm.hostname = n[:nom]
      m.vm.network "private_network", ip: n[:ip]
      m.vm.provider "virtualbox" do |vb|
        vb.memory = n[:mem]
        vb.cpus   = 1
      end
      # Un script par rôle ; ignoré tant qu'il n'existe pas (app.sh, lb.sh à venir).
      script = "scripts/#{n[:role]}.sh"
      m.vm.provision "shell", path: script if File.exist?(File.join(__dir__, script))
    end
  end
end