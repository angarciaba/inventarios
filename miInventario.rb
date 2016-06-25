#!/usr/bin/env ruby
# encoding: utf-8
# File: miInventario.rb
Copyright = 
"Ángel García Baños <angel.garcia@correounivalle.edu.co>\n" +
"Institution: EISC, Universidad del Valle, Colombia\n" +
"Creation date: 2016-06-23\n" +
"Last modification date: 2016-06-25\n" +
"License: GNU-GPL"
Version = "0.2"
Description = "Para verificar mi inventario en la Universidad del Valle. Con una pistola de código de barras (o con el teclado) se van introduciendo los items encontrados en cada espacio. Este software compara lo encontrado con lo que debería estar, y saca un reporte con las diferencias. Para ello lee un archivo en formato .TSV generado por el sistema de inventarios, le añade dos columnas más al inicio (una para el número de veces que se encontró un item: 0==>no se encontró;1==>se encontró;2 o más==>se encontró pero está repetido; negativo==>se encontró pero no está en el archivo, o sea, no es de mi inventario) y lo va actualizando, de modo que se puede ejecutar varias veces y se acuerda de lo realizado hasta entonces."
Dependences = 
"
sudo apt-get install libmagickwand-dev libmagickcore-dev
gem install ftools fileutils
"
#--------------------------------------------------
# VERSIONES
# 0.2 El archivo de entrada se actualiza y se salva, sobreescribiéndolo (antes se saca un backup)
# 0.1 Inicial
#--------------------------------------------------
# Para ayudar a depurar:
def dd(n, a)
  p "[#{n}] #{a.inspect}"
  p "===="
end
#--------------------------------------------------
# Tomado y adaptado del libro Lucas Carlson & Leonard Richardson, "Ruby Cookbook", O'Reilly, USA, 2006.
require 'ftools'
require 'fileutils'

class File
=begin
  def File.versioned_file(base, first_suffix='.000', access_mode='w')
    suffix = file = locked = nil
    filename = base
    begin
      suffix = (suffix ? suffix.succ : first_suffix)
      filename = base + suffix
      unless File.exists? filename
        file = open(filename, access_mode)
        locked = file.flock(File::LOCK_EX | File::LOCK_NB)
        file.close unless locked
      end
    end until locked
    return file
  end
=end

  def File.versioned_filename(base, first_suffix='.000')
    suffix = nil
    filename = base
    while File.exists?(filename)
      suffix = (suffix ? suffix.succ : first_suffix)
      filename = base + suffix
    end
    return filename
  end

  def File.to_backup(filename, move=false)
    new_filename = nil
    if File.exists? filename
      new_filename = File.versioned_filename(filename)
      FileUtils.send(move ? :mv : :cp, filename, new_filename)
    end
    return new_filename
  end
end
#--------------------------------------------------
require 'optparse'

class Argumentos < Hash
  def initialize(args)
    super()
    options = OptionParser.new do |option|
      option.banner = "Use: #$0 [options] [FILE...]\n\n" + Description + "\n\n" + Copyright + "\nVersion: " + Version + "\nOptions:\n" + "Dependences:\n" + Dependences

      option.on('-e=ARG', '--espacios=ARG', 'read a two-column TSV file containing rooms with its equivalent names') do |arg|
        self[:espacios] = arg
      end

      option.on('-b', '--verbose', 'prints all results on screen') do
        self[:verbose] = true
        exit
      end

      option.on('-v', '--version', 'shows version and quits') do
        puts Version
        exit
      end

      option.on_tail('-h', '--help', 'shows this help and quits') do
        puts option
        exit
      end
    end
    options.parse!(args)
  end
end

#--------------------------------------------------
class Inventario
  Archivo_Encontrado = 0
  Archivo_NuevoEspacio = 1
  Archivo_Fecha = 2
  Archivo_NumeroInventario = 3
  Archivo_Espacio = 6

  def initialize(archivoEntrada, archivoEspacios, separador, verbose)
    @archivoEntrada, @archivoEspacios, @separador, @verbose = archivoEntrada, archivoEspacios, separador, verbose
    @inventarioEnElSistema = leerArchivo(@archivoEntrada)
    @equivalenciaEspacios = leerEspacios(@archivoEspacios) if @archivoEspacios
  end
  
  def interactivo
    puts "Introduce (por teclado o pistola de código de barras) el espacio donde vas a trabajar y los items que encuentres. Puedes cambiar de espacio en cualquier momento. Teclea ENTER para terminar."
    loop do
      print "\n>     "
      numeroCapturado = $stdin.gets.chomp.to_s
      if numeroCapturado.empty?
        break
      elsif esEspacio?(numeroCapturado)
        @espacio = numeroCapturado
        puts "\n=================\nESPACIO: #{@espacio}\n================="
      elsif not @espacio
        puts "Entrada ignorada. Por favor, primero teclea el ESPACIO físico donde vas a escanear items (c): "
      else 
        print "ITEM: #{numeroCapturado}"
        indice = buscar(numeroCapturado)
        if (not indice)
          print "  NO está en tu inventario. ¿Qué es? (pulsa ENTER para ignorarlo, si se trata de un error): "
          nombre = $stdin.gets.chomp.to_s
          next if nombre.empty?
          @inventarioEnElSistema << [-1, "", "", numeroCapturado, "", "", @espacio, nombre, "" ]
        elsif @inventarioEnElSistema[indice][Archivo_Encontrado] < 0
          print "  NO está en tu inventario. Y ya lo has escaneado antes. ¿Qué es? (pulsa ENTER para ignorarlo, si se trata de un error): "
          nombre = $stdin.gets.chomp.to_s
          next if nombre.empty?
          @inventarioEnElSistema[indice][Archivo_Encontrado] = @inventarioEnElSistema[indice][Archivo_Encontrado] - 1
          @inventarioEnElSistema[indice][Archivo_NuevoEspacio] << "#{@espacio}#{nombre ? "=" : ""}#{nombre} " unless iguales(@espacio, @inventarioEnElSistema[indice][Archivo_Espacio])
        else
          print "  ENCONTRADO"
          @inventarioEnElSistema[indice][Archivo_Encontrado] = @inventarioEnElSistema[indice][Archivo_Encontrado] + 1
          if @inventarioEnElSistema[indice][Archivo_Encontrado] > 1
            print "  Ya lo has escaneado antes. ¿Qué es? (pulsa ENTER para ignorarlo, si se trata de un error): "
            nombre = $stdin.gets.chomp.to_s
            next if nombre.empty?
          else
            nombre = nil
          end
          @inventarioEnElSistema[indice][Archivo_NuevoEspacio] << "#{@espacio}#{nombre ? "=" : ""}#{nombre} " unless iguales(@espacio, @inventarioEnElSistema[indice][Archivo_Espacio])
        end
        puts
      end
    end
  end
  
  def imprimirReporte
    encontrados = []
    noEncontrados = []
    encontradosPeroNoSonMios = []

    # Hacer backup y salvar archivo
    File.to_backup(@archivoEntrada, true)
    open(@archivoEntrada, "w") do |file|
      @inventarioEnElSistema.each do |item|
        item.each { |columna| file << "#{columna}#{@separador}" }
        file << "\n"
        if @verbose
          if item[Archivo_Encontrado] == 0
            noEncontrados << item
          elsif item[Archivo_Encontrado] < 0
            encontradosPeroNoSonMios << item
          else
            encontrados << item
          end
        end
      end
    end

    if @verbose
      puts "\n===================================================================================="
      puts "ITEMS QUE NO SON DE TU INVENTARIO, PERO QUE HEMOS ENCONTRADO EN LOS ESPACIOS REALES:" unless encontradosPeroNoSonMios.empty?
      encontradosPeroNoSonMios.each { |item| item.each { |x| print "#{x}#{@separador}" };puts }
      puts "\n============================================"
      puts "ITEMS NO ENCONTRADOS EN LOS ESPACIOS REALES:" unless noEncontrados.empty?
      noEncontrados.each { |item| item.each { |x| print "#{x}#{@separador}" };puts }
      puts "\n========================================="
      puts "ITEMS ENCONTRADOS EN LOS ESPACIOS REALES:" unless encontrados.empty?
      encontrados.each { |item| item.each { |x| print "#{x}#{@separador}" };puts }
    end
  end
  
  private
  
  def leerArchivo(archivo)
    listaItems = []
    open(archivo).each do |linea|
      descripcion = linea.strip.split(@separador)
      descripcion.collect {|x| x.strip! }
      if descripcion[0] =~ /\d\d\d\d-\d\d-\d\d/
        listaItems << [0, "", descripcion].flatten  # La primera columna con un 0 es el contador de veces que se ha encontrado este item en los espacios reales. Lo habitual es que valga 0 (no encontrado) o 1 (encontrado), pero podría valer más de 1 si hay etiquetas de inventario repetidas en los items reales. O negativo cuando se encuentren items que no están en mi inventario. La segunda columna es el espacio donde se encontró, en el caso de que no coincida con el espacio donde debería estar (columna 7 después de introducir estas 2 columnas)
      elsif descripcion[Archivo_Fecha] =~ /\d\d\d\d-\d\d-\d\d/
        listaItems << descripcion  # El archivo ya tiene las dos primeras columnas
      else
        # Las líneas que no tienen ese formato se ignoran. ToDo: Salvarlas, porque sirven para documentar.???
      end
    end
    listaItems
  end
  
  def buscar(numeroInventario)
    @inventarioEnElSistema.each_index do |indice| 
      return indice if (@inventarioEnElSistema[indice][Archivo_NumeroInventario] == numeroInventario or @inventarioEnElSistema[indice][Archivo_NumeroInventario] + "00" == numeroInventario or @inventarioEnElSistema[indice][Archivo_NumeroInventario] == numeroInventario + "00")
    end
    return false
  end

  def leerEspacios(archivo)
    equivalencias = {}
    open(archivo).each do |linea|
      descripcion = linea.strip.split(@separador)
      descripcion.collect {|x| x.strip }
      equivalencias[descripcion[0]] = descripcion[1]
    end
    equivalencias
  end
  
  def iguales(espacio1, espacio2)
    return false unless espacio1
    return false unless espacio2
    espacio1.downcase
    espacio2.downcase
    return true if espacio1.downcase.include?(espacio2)
    return true if espacio2.downcase.include?(espacio1)
    return true if @equivalenciaEspacios[@espacio1] and @equivalenciaEspacios[@espacio1].downcase.include?(espacio2)
    return true if @equivalenciaEspacios[@espacio2] and @equivalenciaEspacios[@espacio2].downcase.include?(espacio1)
    return false
  end
  
  def esEspacio?(espacio)
    espacio.downcase!
    @equivalenciaEspacios.each do |key, value|
      return true if key.downcase.include?(espacio)
      return true if value.downcase.include?(espacio)
    end
    return false
  end
end

#--------------------------------------------------
# Main program
if __FILE__ == $0
  separador = "\t"
  argumentos = Argumentos.new(ARGV)
  archivos = ARGV
  archivos.each do |archivoEntrada|
    inventario = Inventario.new(archivoEntrada, argumentos[:espacios], separador, argumentos[:verbose])
    inventario.interactivo
    inventario.imprimirReporte
  end
end


