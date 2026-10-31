class_name MilitaryRegistry
extends RefCounted
## Modules militaires remplaçables : modèle des forces, résolution des combats et IA militaire. Un mod ou un
## DLC remplace un module en y mettant sa propre sous-classe avant le début de la partie (l'interface se
## remplace de la même façon côté UI, voir MilitaryUI).

var model: MilitaryModel = MilitaryModel.new()
var resolver: WarResolver = WarResolver.new()
var ai: MilitaryAI = MilitaryAI.new()
